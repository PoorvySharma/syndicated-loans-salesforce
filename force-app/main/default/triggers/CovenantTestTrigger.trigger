/** Derives Pass/Breach from threshold, then rolls the covenant status. */
trigger CovenantTestTrigger on Covenant_Test__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        CovenantService.evaluate(Trigger.new);
    } else {
        Set<Id> ids = new Set<Id>();
        for (Covenant_Test__c t : Trigger.new) {
            ids.add(t.Covenant__c);
        }
        CovenantService.rollStatus(ids);
    }
}
