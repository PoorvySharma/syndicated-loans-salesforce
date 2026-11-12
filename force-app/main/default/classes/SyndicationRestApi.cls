/**
 * Inbound integration endpoint. POST /services/apexrest/syndication/v1/{drawdowns|rates}
 * Payload schemas: schemas/api/*.schema.json. Requires the Syndication_Operate custom permission.
 */
@RestResource(urlMapping='/syndication/v1/*')
global with sharing class SyndicationRestApi {
    public class DrawdownRequest {
        public Id facilityId;
        public Decimal amount;
        public Date valueDate;
    }

    public class RateFixing {
        public Id interestPeriodId;
        public Decimal baseRatePct;
        public Boolean calculate;
    }

    @HttpPost
    global static void handle() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        res.statusCode = 200;
        Map<String, Object> out = new Map<String, Object>();
        try {
            if (!SyndicationSecurity.isOperator()) {
                res.statusCode = 403;
                out.put('error', 'Missing Syndication_Operate permission.');
            } else {
                String path = RestContext.request.requestURI.substringAfterLast('/');
                String body = RestContext.request.requestBody.toString();
                switch on path {
                    when 'drawdowns' {
                        DrawdownRequest r = (DrawdownRequest) JSON.deserialize(body, DrawdownRequest.class);
                        Drawdown__c d = DrawdownService.request(r.facilityId, r.amount, r.valueDate);
                        d = DrawdownService.notifyLenders(d.Id);
                        out.put('id', d.Id);
                        out.put('status', d.Status__c);
                        out.put('rejectionReason', d.Rejection_Reason__c);
                    }
                    when 'rates' {
                        RateFixing r = (RateFixing) JSON.deserialize(body, RateFixing.class);
                        Interest_Period__c p = InterestService.fixRate(r.interestPeriodId, r.baseRatePct);
                        if (r.calculate == true) {
                            p = InterestService.calculate(p.Id);
                        }
                        out.put('id', p.Id);
                        out.put('status', p.Status__c);
                        out.put('interestAmount', p.Interest_Amount__c);
                    }
                    when else {
                        res.statusCode = 404;
                        out.put('error', 'Unknown resource: ' + path);
                    }
                }
            }
        } catch (Exception ex) {
            res.statusCode = 400;
            out = new Map<String, Object>{ 'error' => ex.getMessage() };
        }
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}
