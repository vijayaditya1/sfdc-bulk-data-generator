public with sharing class CSVRecordBatch implements Database.Batchable<Integer>, Database.StateFul, Database.AllowsCallouts {

    private String objectName;
    private Integer recordCount;
    private List<String> selectedFields;
    private Map<String, Schema.SObjectField> fieldMap;
    private Map<String, List<Id>> referenceIds;
    private Integer optimalBatchSize;

    public CSVRecordBatch(String objectName, Integer recordCount, List<String> selectedFields,
                        Map<String, Schema.SObjectField> fieldMap,
                        Map<String, List<Id>> referenceIds) {
        this.objectName = objectName;
        this.recordCount = recordCount;
        this.selectedFields = selectedFields;
        this.fieldMap = fieldMap;
        this.referenceIds = referenceIds;
    }

    public Iterable<Integer> start(Database.BatchableContext context) {

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

        this.optimalBatchSize = Math.min(Math.min(maxByHeap, maxByCpu), maxByCsv);
        System.debug('Optimal batch size: ' + optimalBatchSize);

        this.optimalBatchSize = 10;

        List<Integer> startIndexes = new List<Integer>();
        for (Integer i = 0; i < recordCount; i += optimalBatchSize) {
            startIndexes.add(i);
        }
        return startIndexes;
    }

    public void execute(Database.BatchableContext context, List<Integer> scope) {
        Integer startIdx = scope[0];
        Integer endIdx = Math.min(startIdx + this.optimalBatchSize, recordCount);

        Map<String, Schema.DescribeFieldResult> fieldDescribeMap = new Map<String, Schema.DescribeFieldResult>();
        for (String fieldName : selectedFields) {
            fieldDescribeMap.put(fieldName, fieldMap.get(fieldName).getDescribe());
        }

        List<String> csvRows = new List<String>();
        csvRows.add(String.join(selectedFields, ','));

        for (Integer i = startIdx; i < endIdx; i++) {
            List<String> row = new List<String>();
            for (String fieldName: selectedFields) {
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
            csvRows.add(String.join(row, ','));
        }

        String csvContent = String.join(csvRows, '\n');
        System.debug('csvContent: ' + csvContent);
        createBulkJob(objectName, csvContent);
    }

    public void finish(Database.BatchableContext context) {
        System.debug('CSV batch finished');
    }

    public static String createBulkJob(String objectName, String csvContent) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        // Get the page content (this triggers server-side page rendering)
        String sessionId = Page.SessionId.getContent().toString().trim();
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
        dataReq.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest/' + jobId + '/batches');
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
        closeReq.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest/' + jobId);
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

    private static AuraHandledException getException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }
}