//sample class, not actually needed
//record deletion
//check bulk api failed result RecordDeleteBatch.jobCheck('750gD000000jrWQ');
public class RecordDeleteBatch implements Database.Batchable<Integer>, Database.AllowsCallouts {

    private String sobj;
    
    public RecordDeleteBatch(String sobj) {
        this.sobj = sobj;
    }
    
    public Iterable<Integer> start(Database.BatchableContext BC) {
        Integer j = Database.countQuery('select count() from ' + sobj) / 10000;
        List<Integer> l = new List<Integer>();
        for (Integer i=0; i<=j; i++) {
            l.add(i);
        }
        return l;
    }

    public void execute(Database.BatchableContext BC, List<Integer> scope) {
        // Cast to correct object type and delete
        //Database.delete(Database.query('SELECT Id FROM ' + sobj + ' limit 10000'), false);
        createBulkJob();
    }
    
    public void createBulkJob() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        // Get the page content (this triggers server-side page rendering)
        String sessionId = Page.SessionId.getContent().toString().trim();
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        
        Map<String, String> jobInfo = new Map<String, String>{
            'object' => sobj,
            'contentType' => 'CSV',
            'operation' => 'delete',
            'lineEnding' => 'LF'
        };
        
        req.setBody(JSON.serialize(jobInfo));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug(res.getBody());
        
        if (res.getStatusCode() != 200) {
            //throw getException('Failed to create bulk job: ' + res.getBody());
        }
        
        Map<String, Object> jobResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String jobId = (String) jobResponse.get('id');
        
        String csvContent = 'Id\n' + String.join(new Map<Id, SObject>(Database.query('SELECT Id FROM ' + sobj + ' limit 50000')).keySet(), '\n');
        
        // Upload CSV data
        HttpRequest dataReq = new HttpRequest();
        dataReq.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest/' + jobId + '/batches');
        dataReq.setMethod('PUT');
        dataReq.setHeader('Content-Type', 'text/csv');
        dataReq.setHeader('Authorization', 'Bearer ' + sessionId);
        dataReq.setBody(csvContent);
        
        HttpResponse dataRes = http.send(dataReq);
        
        if (dataRes.getStatusCode() != 201) {
            //throw getException('Failed to upload CSV data: ' + dataRes.getBody());
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
            //throw getException('Failed to close bulk job: ' + closeRes.getBody());
        }
    }

    public void finish(Database.BatchableContext BC) {
        // Optional: send email or log result
        System.debug('Finished deleting all Custom_Object__c records.');
    }
    
    public static void jobCheck(Id jobId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(MockDataUtil.BASE_URL + '/services/data/v64.0/jobs/ingest/' + jobId + '/failedResults');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        System.debug(new Http().send(req).getBody());
    }
}