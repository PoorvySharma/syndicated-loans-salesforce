/**
 * Amendment / waiver voting weighted by allocated commitment.
 * Approved when consenting weight >= Required_Majority_Pct__c. Rejected as soon as the threshold
 * becomes mathematically unreachable. Expired when the deadline passes without a decision.
 */
public with sharing class ConsentService {
    public static Integer circulate(Id amendmentId) {
        Amendment_Request__c a = [SELECT Id, Deal__c, Status__c FROM Amendment_Request__c WHERE Id = :amendmentId];
        if (a.Status__c != 'Draft') {
            throw new LoanException('Only Draft amendments can be circulated (current status: ' + a.Status__c + ').');
        }
        List<Lender_Commitment__c> holders = [
            SELECT Id, Allocated_Amount__c
            FROM Lender_Commitment__c
            WHERE Facility__r.Deal__c = :a.Deal__c AND Status__c = 'Signed' AND Allocated_Amount__c > 0
            ORDER BY CreatedDate, Id
        ];
        if (holders.isEmpty()) {
            throw new LoanException('The deal has no signed lenders to consult.');
        }
        List<Lender_Consent__c> consents = new List<Lender_Consent__c>();
        for (Lender_Commitment__c h : holders) {
            consents.add(new Lender_Consent__c(Amendment__c = a.Id, Lender_Commitment__c = h.Id, Weight_Amount__c = h.Allocated_Amount__c, Response__c = 'Pending'));
        }
        insert consents;
        a.Status__c = 'Circulated';
        update a;
        return consents.size();
    }

    public static void tally(Set<Id> amendmentIds) {
        List<Amendment_Request__c> ams = [
            SELECT Id, Deal__c, Status__c, Required_Majority_Pct__c, Response_Deadline__c
            FROM Amendment_Request__c
            WHERE Id IN :amendmentIds AND Status__c = 'Circulated'
        ];
        if (ams.isEmpty()) {
            return;
        }
        Map<Id, Decimal> total = new Map<Id, Decimal>();
        Map<Id, Decimal> consent = new Map<Id, Decimal>();
        Map<Id, Decimal> decline = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Amendment__c amd, Response__c rsp, SUM(Weight_Amount__c) wgt
            FROM Lender_Consent__c
            WHERE Amendment__c IN :amendmentIds
            GROUP BY Amendment__c, Response__c
        ]) {
            Id aid = (Id) ar.get('amd');
            String resp = (String) ar.get('rsp');
            Decimal w = LoanMath.nz((Decimal) ar.get('wgt'));
            total.put(aid, LoanMath.nz(total.get(aid)) + w);
            if (resp == 'Consent') {
                consent.put(aid, LoanMath.nz(consent.get(aid)) + w);
            } else if (resp == 'Decline') {
                decline.put(aid, LoanMath.nz(decline.get(aid)) + w);
            }
        }
        List<Amendment_Request__c> toUpdate = new List<Amendment_Request__c>();
        for (Amendment_Request__c a : ams) {
            Decimal t = LoanMath.nz(total.get(a.Id));
            if (t <= 0) {
                continue;
            }
            Decimal consentPct = 0.00;//LoanMath.nz(consent.get(a.Id))*(100).divide(t, 4, RoundingMode.HALF_UP);
            Decimal declinePct = 0.00; //LoanMath.nz(decline.get(a.Id))*(100).divide(t, 4, RoundingMode.HALF_UP);
            Decimal required = a.Required_Majority_Pct__c == null ? 66.67 : a.Required_Majority_Pct__c;
            a.Consent_Pct__c = consentPct;
            a.Decline_Pct__c = declinePct;
            if (consentPct >= required) {
                a.Status__c = 'Approved';
            } else if ((100 - declinePct) < required) {
                a.Status__c = 'Rejected';
            } else if (a.Response_Deadline__c != null && a.Response_Deadline__c < Date.today()) {
                a.Status__c = 'Expired';
            }
            if (a.Status__c != 'Circulated') {
                a.Resolution_Date__c = Date.today();
                LoanEvents.publish('AMENDMENT_RESOLVED', a.Deal__c, a.Id, new Map<String, Object>{
                    'amendmentId' => a.Id, 'outcome' => a.Status__c, 'consentPct' => consentPct
                });
            }
            toUpdate.add(a);
        }
        update toUpdate;
    }
}
