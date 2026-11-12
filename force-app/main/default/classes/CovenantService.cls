/**
 * Covenant testing. Result is derived from the covenant's direction/threshold; the covenant's
 * status follows its most recent test. Breaches raise a platform event.
 */
public with sharing class CovenantService {
    public static void evaluate(List<Covenant_Test__c> tests) {
        Set<Id> cids = new Set<Id>();
        for (Covenant_Test__c t : tests) {
            cids.add(t.Covenant__c);
        }
        Map<Id, Covenant__c> cov = new Map<Id, Covenant__c>([SELECT Id, Operator__c, Threshold__c FROM Covenant__c WHERE Id IN :cids]);
        for (Covenant_Test__c t : tests) {
            Covenant__c c = cov.get(t.Covenant__c);
            if (t.Result__c == 'Waived' || c == null || c.Threshold__c == null || t.Actual_Value__c == null) {
                continue;
            }
            Boolean ok = c.Operator__c == 'Minimum' ? t.Actual_Value__c >= c.Threshold__c : t.Actual_Value__c <= c.Threshold__c;
            t.Result__c = ok ? 'Pass' : 'Breach';
        }
    }

    public static void rollStatus(Set<Id> covenantIds) {
        Map<Id, Covenant__c> cov = new Map<Id, Covenant__c>([SELECT Id, Deal__c, Status__c FROM Covenant__c WHERE Id IN :covenantIds]);
        Map<Id, Covenant_Test__c> latest = new Map<Id, Covenant_Test__c>();
        for (Covenant_Test__c t : [
            SELECT Id, Covenant__c, Result__c, Actual_Value__c, Covenant__r.Threshold__c
            FROM Covenant_Test__c
            WHERE Covenant__c IN :covenantIds AND Result__c != NULL
            ORDER BY Test_Date__c DESC, CreatedDate DESC
        ]) {
            if (!latest.containsKey(t.Covenant__c)) {
                latest.put(t.Covenant__c, t);
            }
        }
        List<Covenant__c> toUpdate = new List<Covenant__c>();
        for (Id cid : latest.keySet()) {
            Covenant_Test__c t = latest.get(cid);
            Covenant__c c = cov.get(cid);
            String next = t.Result__c == 'Pass' ? 'Compliant' : (t.Result__c == 'Breach' ? 'Breached' : 'Waived');
            if (c.Status__c != next) {
                c.Status__c = next;
                toUpdate.add(c);
                if (next == 'Breached') {
                    LoanEvents.publish('COVENANT_BREACH', c.Deal__c, c.Id, new Map<String, Object>{
                        'covenantId' => c.Id, 'testId' => t.Id, 'actual' => t.Actual_Value__c, 'threshold' => t.Covenant__r.Threshold__c
                    });
                }
            }
        }
        update toUpdate;
    }
}
