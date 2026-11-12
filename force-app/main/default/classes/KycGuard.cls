/**
 * Compliance gate. An institution is eligible only with a current (non-expired) Passed
 * KYC check AND a Passed Sanctions check.
 */
public with sharing class KycGuard {
    public static final Set<String> REQUIRED = new Set<String>{ 'KYC', 'Sanctions' };

    public static Set<Id> eligible(Set<Id> accountIds) {
        Date asOf = Date.today();
        Map<Id, Set<String>> passed = new Map<Id, Set<String>>();
        for (KYC_Check__c c : [
            SELECT Account__c, Check_Type__c
            FROM KYC_Check__c
            WHERE Account__c IN :accountIds AND Status__c = 'Passed' AND (Expiry_Date__c = NULL OR Expiry_Date__c >= :asOf)
        ]) {
            if (!passed.containsKey(c.Account__c)) {
                passed.put(c.Account__c, new Set<String>());
            }
            passed.get(c.Account__c).add(c.Check_Type__c);
        }
        Set<Id> ok = new Set<Id>();
        for (Id acc : passed.keySet()) {
            if (passed.get(acc).containsAll(REQUIRED)) {
                ok.add(acc);
            }
        }
        return ok;
    }
}
