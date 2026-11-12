/**
 * Bookbuilding allocation. Pro-rata cut-back of soft commitments when oversubscribed,
 * with KYC/sanctions screening. Idempotent: may be re-run until the facility is closed.
 */
public with sharing class SyndicationAllocator {
    public class Line {
        @AuraEnabled public Id commitmentId;
        @AuraEnabled public String lender;
        @AuraEnabled public Decimal softCommit;
        @AuraEnabled public Decimal allocated;
    }

    public class Result {
        @AuraEnabled public Id facilityId;
        @AuraEnabled public Decimal commitment;
        @AuraEnabled public Decimal totalSoftCommit;
        @AuraEnabled public Decimal totalAllocated;
        @AuraEnabled public Decimal cutBackPct;
        @AuraEnabled public Boolean oversubscribed;
        @AuraEnabled public Boolean fullyAllocated;
        @AuraEnabled public List<Line> lines = new List<Line>();
        @AuraEnabled public List<String> blocked = new List<String>();
    }

    public static Result allocate(Id facilityId) {
        Facility__c f = [SELECT Id, Deal__c, Status__c, Commitment_Amount__c FROM Facility__c WHERE Id = :facilityId];
        if (f.Status__c == 'Active' || f.Status__c == 'Repaid' || f.Status__c == 'Cancelled') {
            throw new LoanException('Allocation is closed: facility is ' + f.Status__c + '.');
        }
        List<Lender_Commitment__c> all = [
            SELECT Id, Lender__c, Lender__r.Name, Soft_Commit_Amount__c, Allocated_Amount__c, Status__c
            FROM Lender_Commitment__c
            WHERE Facility__c = :facilityId
            ORDER BY CreatedDate, Id
        ];
        Set<Id> candidates = new Set<Id>();
        for (Lender_Commitment__c lc : all) {
            if (lc.Status__c == 'Soft Committed' || lc.Status__c == 'Allocated') {
                candidates.add(lc.Lender__c);
            }
        }
        Set<Id> eligible = KycGuard.eligible(candidates);

        Result r = new Result();
        r.facilityId = f.Id;
        r.commitment = f.Commitment_Amount__c;
        List<Lender_Commitment__c> inScope = new List<Lender_Commitment__c>();
        List<Lender_Commitment__c> toUpdate = new List<Lender_Commitment__c>();
        for (Lender_Commitment__c lc : all) {
            Boolean live = lc.Status__c == 'Soft Committed' || lc.Status__c == 'Allocated';
            if (!live) {
                // Declined / withdrawn / invited: make sure no stale allocation remains.
                if (LoanMath.nz(lc.Allocated_Amount__c) != 0) {
                    lc.Allocated_Amount__c = 0;
                    toUpdate.add(lc);
                }
            } else if (!eligible.contains(lc.Lender__c)) {
                r.blocked.add(lc.Lender__r.Name);
                if (lc.Status__c == 'Allocated' || LoanMath.nz(lc.Allocated_Amount__c) != 0) {
                    lc.Allocated_Amount__c = 0;
                    lc.Status__c = 'Soft Committed';
                    toUpdate.add(lc);
                }
            } else {
                inScope.add(lc);
            }
        }
        if (inScope.isEmpty()) {
            throw new LoanException(
                'No eligible soft commitments to allocate' +
                (r.blocked.isEmpty() ? '.' : ' (blocked by KYC/sanctions: ' + String.join(r.blocked, ', ') + ').')
            );
        }

        List<Decimal> softs = new List<Decimal>();
        Decimal totalSoft = 0.00;
        for (Lender_Commitment__c lc : inScope) {
            Decimal s = LoanMath.nz(lc.Soft_Commit_Amount__c);
            softs.add(s);
            totalSoft += s;
        }
        r.totalSoftCommit = totalSoft;
        r.oversubscribed = totalSoft > f.Commitment_Amount__c;
        List<Decimal> alloc = r.oversubscribed ? LoanMath.split(f.Commitment_Amount__c, softs) : softs;
        //r.cutBackPct = r.oversubscribed ? f.Commitment_Amount__c*(100).divide(1.25, 2, RoundingMode.HALF_UP) : 100;

        Decimal total = 0;
        for (Integer i = 0; i < inScope.size(); i++) {
            Lender_Commitment__c lc = inScope[i];
            lc.Allocated_Amount__c = alloc[i];
            lc.Status__c = alloc[i] > 0 ? 'Allocated' : 'Soft Committed';
            total += alloc[i];
            Line ln = new Line();
            ln.commitmentId = lc.Id;
            ln.lender = lc.Lender__r.Name;
            ln.softCommit = softs[i];
            ln.allocated = alloc[i];
            r.lines.add(ln);
            toUpdate.add(lc);
        }
        r.totalAllocated = total;
        r.fullyAllocated = total >= f.Commitment_Amount__c;
        update toUpdate;

        f.Status__c = r.fullyAllocated ? 'Allocated' : 'Open for Commitments';
        update f;

        LoanEvents.publish(
            'FACILITY_ALLOCATED',
            f.Deal__c,
            f.Id,
            new Map<String, Object>{
                'facilityId' => f.Id,
                'commitment' => r.commitment,
                'totalSoftCommit' => r.totalSoftCommit,
                'totalAllocated' => r.totalAllocated,
                'cutBackPct' => r.cutBackPct,
                'blockedLenders' => r.blocked
            }
        );
        return r;
    }
}
