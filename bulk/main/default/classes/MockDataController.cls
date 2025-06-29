public with sharing class MockDataController {

    public static final Integer MAX_RECORDS = 4000000;
    
    public static final Integer HEAP_LIMIT = Limits.getLimitHeapSize();
    public static final Integer TIME_LIMIT = Limits.getLimitCpuTime();

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
            throw MockDataUtil.getException('Error retrieving objects: ' + e.getMessage());
        }
    }

    // Get object fields metadata
    @AuraEnabled(cacheable=true)
    public static List<MockDataUtil.FieldConfig> getObjectFields(String objectName) {
        try {
            List<MockDataUtil.FieldConfig> fields = new List<MockDataUtil.FieldConfig>();
            
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            if (sObjectType == null) {
                throw MockDataUtil.getException('Invalid object name');
            }

            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
                if (field.isCreateable()) {
                    fields.add(new MockDataUtil.FieldConfig(field.getLabel(), field.getName()));
                }
            }
            return fields;
        } catch (Exception e) {
            throw MockDataUtil.getException('Error retrieving fields: ' + e.getMessage());
        }
    }

    // Generate and insert mock records using Bulk API v2
    @AuraEnabled
    public static String generateMockRecords(String objectName, List<String> selectedFields, Integer recordCount) {

        try {
            if (recordCount > MAX_RECORDS) {
                throw MockDataUtil.getException('Record count exceeds maximum limit of 4,000,000');
            }
            Integer numReferenceRecords = (recordCount / 100000) + 1;

            // Get field metadata
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

            // Identify referenced objects
            Map<String, List<String>> referenceFields = new Map<String, List<String>>(); // refObjName -> list of field names
            for (Schema.SObjectField field : fieldMap.values()) {
                Schema.DescribeFieldResult describeResult = field.getDescribe();
                if (describeResult.isCreateable() && !describeResult.isNillable() && !describeResult.isDefaultedOnCreate() && !selectedFields.contains(describeResult.getName())) {
                    selectedFields.add(describeResult.getName());
                }
                if (selectedFields.contains(describeResult.getName()) && describeResult.getType() == Schema.DisplayType.REFERENCE) {
                    String refObj = describeResult.getReferenceTo().isEmpty() ? null : describeResult.getReferenceTo()[0].getDescribe().getName();
                    if (refObj != null) {
                        if (!referenceFields.containsKey(refObj)) {
                            referenceFields.put(refObj, new List<String>());
                        }
                        referenceFields.get(refObj).add(describeResult.getName());
                    }
                }
            }

            // 1. Generate referenced records and store their IDs
            List<SObject> refAllRecords = new List<SObject>();
            Map<String, List<Id>> referenceIds = new Map<String, List<Id>>();
            for (String refObj : referenceFields.keySet()) {
                List<SObject> refRecords = new List<SObject>();
                Schema.SObjectType refType = Schema.getGlobalDescribe().get(refObj);
                Map<String, Schema.SObjectField> refFieldMap = refType.getDescribe().fields.getMap();
                for (Integer i = 0; i < numReferenceRecords; i++) {
                    SObject rec = refType.newSObject();
                    // Populate required fields with random data
                    for (Schema.SObjectField f : refFieldMap.values()) {
                        Schema.DescribeFieldResult d = f.getDescribe();
                        if (!d.isNillable() && !d.isDefaultedOnCreate()) {
                            rec.put(d.getName(), MockDataUtil.generateFieldValue(d));
                        }
                    }
                    refRecords.add(rec);
                }
                if (!refRecords.isEmpty()) {
                    refAllRecords.addAll(refRecords);
                    referenceIds.put(refObj, new List<Id>());
                }
            }
            insert refAllRecords;
            for (SObject rec : refAllRecords) {
                referenceIds.get(MockDataUtil.getDescribe(rec.Id.getSObjectType()).getName()).add((Id) rec.get('Id'));
            }

            CSVRecordBatch batchJob = new CSVRecordBatch(objectName, recordCount, selectedFields, fieldMap, referenceIds);
            return Database.executeBatch(batchJob, 1);
        } catch (Exception e) {
            throw MockDataUtil.getException('Error generating records: ' + e.getMessage());
        }
    }

    /*public class BatchSizeEstimatorQueue implements Queueable, Database.AllowsCallouts {

        private String objectName;
        private Integer recordCount;
        private List<String> selectedFields;
        private Map<String, Schema.SObjectField> fieldMap;
        private Map<String, List<Id>> referenceIds;

        public BatchSizeEstimatorQueue(String objectName, Integer recordCount, List<String> selectedFields,
                                    Map<String, Schema.SObjectField> fieldMap,
                                    Map<String, List<Id>> referenceIds) {
            this.objectName = objectName;
            this.recordCount = recordCount;
            this.selectedFields = selectedFields;
            this.fieldMap = fieldMap;
            this.referenceIds = referenceIds;
        }

        public void execute(QueueableContext context) {
            // Sample N records to estimate
            Integer sampleSize = 20;
            Integer heapStart = Limits.getHeapSize();
            Long cpuStart = Limits.getCpuTime();

            Map<String, Schema.DescribeFieldResult> fieldDescribeMap = new Map<String, Schema.DescribeFieldResult>();
            for (String fieldName : selectedFields) {
                fieldDescribeMap.put(fieldName, fieldMap.get(fieldName).getDescribe());
            }

            List<String> rows = new List<String>();

            for (Integer i = 0; i < sampleSize; i++) {
                List<String> row = new List<String>();
                for (String fieldName : selectedFields) {
                    Schema.DescribeFieldResult field = fieldDescribeMap.get(fieldName);
                    if (field.getType() == Schema.DisplayType.REFERENCE) {
                        String refObj = field.getReferenceTo().isEmpty() ? null : field.getReferenceTo()[0].getDescribe().getName();
                        if (refObj != null && referenceIds.containsKey(refObj) && !referenceIds.get(refObj).isEmpty()) {
                            List<Id> ids = referenceIds.get(refObj);
                            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), ids.size());
                            row.add('"' + String.valueOf(ids[idx]) + '"');
                            continue;
                        }
                    }
                    row.add(MockDataUtil.generateFieldValue(field));
                }
                rows.add(String.join(row, ','));
            }

            Integer heapUsed = Limits.getHeapSize() - heapStart;
            Long cpuUsed = Limits.getCpuTime() - cpuStart;
            Integer csvSize = String.join(rows, '\n').length();

            // Estimate per record
            Decimal heapPerRecord = heapUsed / (Decimal)sampleSize;
            Decimal cpuPerRecord = cpuUsed / (Decimal)sampleSize;
            Decimal avgCsvSizePerRecord = csvSize / (Decimal)sampleSize;

            // Use safe thresholds (heap: 3500000, cpu: 40000, csv: 100MB)
            Integer safeHeapLimit = 3500000;
            Integer safeCpuLimit = 40000;
            Integer safeCsvSize = 100000000; //approx

            Integer maxByHeap = Math.floor(safeHeapLimit / heapPerRecord).intValue();
            Integer maxByCpu = Math.floor(safeCpuLimit / cpuPerRecord).intValue();
            Integer maxByCsv = Math.floor(safeCsvSize / avgCsvSizePerRecord).intValue();

            Integer optimalBatchSize = Math.min(Math.min(maxByHeap, maxByCpu), maxByCsv);
            System.debug('Optimal batch size: ' + optimalBatchSize);

            // Now execute the batch with the calculated size
            //CSVRecordBatch batchJob = new CSVRecordBatch(objectName, recordCount, selectedFields, fieldMap, referenceIds, optimalBatchSize);
            //Database.executeBatch(batchJob, 1);
        }
    }*/

    // Check job status
    @AuraEnabled
    public static AsyncApexJob checkJobStatus(String jobId) {
        try {

            List<AsyncApexJob> job = [SELECT Id, ApexClassId, jobtype, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors FROM AsyncApexJob where Id = :jobId WITH SYSTEM_MODE];
            if (job.isEmpty()) {
                return null;
            }
            return job[0];

            /*HttpRequest req = new HttpRequest();
            req.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest/' + jobId);
            String sessionId = Page.SessionId.getContent().toString().trim();
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setMethod('GET');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() != 200) {
                throw MockDataUtil.getException('Failed to check job status: ' + res.getBody());
            }
            
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());*/
        } catch (Exception e) {
            //throw MockDataUtil.getException('Error checking job status: ' + e.getMessage());
            return null;
        }
    }
}