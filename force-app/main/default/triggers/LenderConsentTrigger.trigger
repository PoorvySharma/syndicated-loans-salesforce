/** Stamps response dates and re-tallies the amendment vote whenever consents change. */
trigger LenderConsentTrigger on Lender_Consent__c (before update, after insert, after update) {
    if (Trigger.isBefore) {
        for (Lender_Consent__c c : Trigger.new) {
            if (c.Response__c != Trigger.oldMap.get(c.Id).Response__c && c.Response__c != 'Pending') {
                c.Responded_Date__c = Date.today();
            }
        }
    } else {
        Set<Id> ids = new Set<Id>();
        for (Lender_Consent__c c : Trigger.new) {
            ids.add(c.Amendment__c);
        }
        ConsentService.tally(ids);
    }
}
