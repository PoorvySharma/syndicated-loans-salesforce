/**
 * Publishes Loan_Event__e platform events: the integration + audit backbone.
 * Payload shapes are documented in schemas/events/loan-event.schema.json.
 */
public with sharing class LoanEvents {
    public static void publish(String eventType, Id dealId, Id recordId, Map<String, Object> payload) {
        Loan_Event__e evt = new Loan_Event__e(
            Event_Type__c = eventType,
            Deal_Id__c = dealId == null ? null : String.valueOf(dealId),
            Record_Id__c = recordId == null ? null : String.valueOf(recordId),
            Payload__c = JSON.serialize(payload)
        );
        Database.SaveResult sr = EventBus.publish(evt);
        if (!sr.isSuccess()) {
            throw new LoanException('Failed to publish ' + eventType + ': ' + sr.getErrors()[0].getMessage());
        }
    }
}
