public with sharing class MockDataController {

    public static final Integer MAX_RECORDS = 4000000;
    public static final String baseUrl = URL.getOrgDomainUrl().toExternalForm();

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getObjects() {
        try {
            Map<String, String> objects = new Map<String, String>();
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            for (String objectName : globalDescribe.keySet()) {
                Schema.SObjectType sObjectType = globalDescribe.get(objectName);
                if (sObjectType.getDescribe().isCreateable()) {
                    objects.put(objectName, sObjectType.getDescribe().getLabel());
                }
            }
            return objects;
        } catch (Exception e) {
            throw getException('Error retrieving objects: ' + e.getMessage());
        }
    }

    // Get object fields metadata
    @AuraEnabled(cacheable=true)
    public static List<FieldConfig> getObjectFields(String objectName) {
        try {
            List<FieldConfig> fields = new List<FieldConfig>();
            
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            if (sObjectType == null) {
                throw getException('Invalid object name');
            }

            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
                if (field.isCreateable()) {
                    fields.add(new FieldConfig(field.getLabel(), field.getName()));
                }
            }
            return fields;
        } catch (Exception e) {
            throw getException('Error retrieving fields: ' + e.getMessage());
        }
    }

    // Generate and insert mock records using Bulk API v2
    @AuraEnabled
    public static String generateMockRecords(String objectName, List<String> selectedFields, Integer recordCount) {
        try {
            if (recordCount > 4000000) {
                throw getException('Record count exceeds maximum limit of 4,000,000');
            }

            // Get field metadata
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

            Set<String> objectToCreate = new Set<String>();
            for (Schema.SObjectField field: fieldMap.values()) {
                Schema.DescribeFieldResult describeResult = field.getDescribe();
                //include if the field is required and not selected to create the data for
                if (!describeResult.isNillable() && !describeResult.isDefaultedOnCreate() && !selectedFields.contains(describeResult.getName())) {
                    selectedFields.add(describeResult.getName());
                }
                if (selectedFields.contains(describeResult.getName()) && describeResult.getType() == Schema.DisplayType.REFERENCE) {
                    // If the field is a reference, ensure it is included in the selected fields
                    objectToCreate.add(describeResult.getReferenceTo()[0].getDescribe().getName());
                }
            }

            // Prepare CSV content
            String csvContent = String.join(selectedFields, ',') + '\n';
            for (Integer i = 0; i < recordCount; i++) {
                List<String> row = new List<String>();
                for (String fieldName : selectedFields) {
                    Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
                    row.add(generateFieldValue(field));
                }
                csvContent += String.join(row, ',') + '\n';
            }

            // Create Bulk API v2 job
            String jobId = createBulkJob(objectName, csvContent);
            return jobId;
        } catch (Exception e) {
            throw getException('Error generating records: ' + e.getMessage());
        }
    }

    // Generate random field value based on field type
    private static String generateFieldValue(Schema.DescribeFieldResult field) {
        String fieldType = String.valueOf(field.getType());
        Integer length = field.getLength();
        
        switch on fieldType {
            when 'STRING', 'TEXTAREA' {
                return generateRandomText(Math.min(length, 20));
            }
            when 'EMAIL' {
                return 'test' + generateRandomText(5) + '@test.com';
            }
            when 'PHONE' {
                return generateRandomPhone();
            }
            when 'PICKLIST' {
                List<Schema.PicklistEntry> entries = field.getPicklistValues();
                return entries.isEmpty() ? '' : entries[Math.mod(Math.abs(Crypto.getRandomInteger()), entries.size())].getValue();
            }
            when 'INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT' {
                return String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));
            }
            when 'DATE' {
                return Date.today().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format();
            }
            when 'DATETIME' {
                return DateTime.now().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format();
            }
            when else {
                return '';
            }
        }
    }

    // Generate random string of specified length
    private static String generateRandomText(Integer length) {
        String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        return generateRandomString(chars, length);
    }

    // Generate random phone number
    private static String generateRandomPhone() {
        String chars = '0123456789';
        return generateRandomString(chars, 10);
    }

    private static String generateRandomString(String chars, Integer length) {
        String result = '';
        for (Integer i = 0; i < length; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            result += chars.substring(idx, idx + 1);
        }
        return result;
    }

    // Create Bulk API v2 job
    private static String createBulkJob(String objectName, String csvContent) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/services/data/v64.0/jobs/ingest');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        // Get the page content (this triggers server-side page rendering)
        String sessionId = Page.SessionId.getContent().toString().trim();
        //if (true) throw getException('=>' + sessionId);
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        
        Map<String, String> jobInfo = new Map<String, String>{
            'object' => objectName,
            'contentType' => 'CSV',
            'operation' => 'insert',
            'lineEnding' => 'LF'
        };
        
        req.setBody(JSON.serialize(jobInfo));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 200) {
            throw getException('Failed to create bulk job: ' + res.getBody());
        }
        
        Map<String, Object> jobResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String jobId = (String) jobResponse.get('id');
        
        // Upload CSV data
        HttpRequest dataReq = new HttpRequest();
        dataReq.setEndpoint(baseUrl + '/services/data/v64.0/jobs/ingest/' + jobId + '/batches');
        dataReq.setMethod('PUT');
        dataReq.setHeader('Content-Type', 'text/csv');
        dataReq.setHeader('Authorization', 'Bearer ' + sessionId);
        dataReq.setBody(csvContent);
        
        HttpResponse dataRes = http.send(dataReq);
        
        if (dataRes.getStatusCode() != 201) {
            throw getException('Failed to upload CSV data: ' + dataRes.getBody());
        }
        
        // Close job
        HttpRequest closeReq = new HttpRequest();
        closeReq.setEndpoint(baseUrl + '/services/data/v64.0/jobs/ingest/' + jobId);
        closeReq.setMethod('PATCH');
        closeReq.setHeader('Content-Type', 'application/json');
        closeReq.setHeader('Authorization', 'Bearer ' + sessionId);
        closeReq.setBody('{"state":"UploadComplete"}');
        
        HttpResponse closeRes = http.send(closeReq);
        
        if (closeRes.getStatusCode() != 200) {
            throw getException('Failed to close bulk job: ' + closeRes.getBody());
        }
        
        return jobId;
    }

    // Check job status
    @AuraEnabled
    public static Map<String, Object> checkJobStatus(String jobId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + '/services/data/v64.0/jobs/ingest/' + jobId);
            String sessionId = Page.SessionId.getContent().toString().trim();
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setMethod('GET');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() != 200) {
                throw getException('Failed to check job status: ' + res.getBody());
            }
            
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw getException('Error checking job status: ' + e.getMessage());
        }
    }

    private static AuraHandledException getException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    // Class to hold field metadata and generation logic
    public class FieldConfig {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public FieldConfig(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}