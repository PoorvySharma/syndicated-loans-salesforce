/**
 * Signing/closing: converts Allocated commitments to Signed and activates the facility.
 * Gate: facility fully allocated AND the Agent has confirmed conditions precedent on the deal.
 */
public with sharing class ClosingService {
    public static void close(Id facilityId) {
        Facility__c f = [
            SELECT Id, Deal__c, Deal__r.CPs_Satisfied__c, Status__c, Commitment_Amount__c, Allocated_Amount__c
            FROM Facility__c
            WHERE Id = :facilityId
        ];
        if (f.Status__c != 'Allocated') {
            throw new LoanException('Facility must be Allocated before closing (current status: ' + f.Status__c + ').');
        }
        if (f.Deal__r.CPs_Satisfied__c != true) {
            throw new LoanException('Conditions precedent have not been confirmed on the deal.');
        }
        if (LoanMath.nz(f.Allocated_Amount__c) != f.Commitment_Amount__c) {
            throw new LoanException('Allocated amount ' + f.Allocated_Amount__c + ' does not equal the commitment ' + f.Commitment_Amount__c + '.');
        }
        List<Lender_Commitment__c> lcs = [SELECT Id FROM Lender_Commitment__c WHERE Facility__c = :facilityId AND Status__c = 'Allocated'];
        for (Lender_Commitment__c lc : lcs) {
            lc.Status__c = 'Signed';
        }
        update lcs;
        f.Status__c = 'Active';
        update f;

        Integer notYetActive = [SELECT COUNT() FROM Facility__c WHERE Deal__c = :f.Deal__c AND Status__c NOT IN ('Active', 'Cancelled')];
        if (notYetActive == 0) {
            Syndicated_Deal__c d = [SELECT Id, Closing_Date__c FROM Syndicated_Deal__c WHERE Id = :f.Deal__c];
            d.Stage__c = 'Active';
            if (d.Closing_Date__c == null) {
                d.Closing_Date__c = Date.today();
            }
            update d;
        }
        LoanEvents.publish(
            'FACILITY_CLOSED',
            f.Deal__c,
            f.Id,
            new Map<String, Object>{ 'facilityId' => f.Id, 'commitment' => f.Commitment_Amount__c, 'lenderCount' => lcs.size() }
        );
    }
}
