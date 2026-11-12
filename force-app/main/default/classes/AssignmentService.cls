/**
 * Secondary-market assignment settlement. Moves allocated (and pro-rata funded) amounts from the seller's
 * commitment to the buyer's. Buyer must pass KYC/Sanctions. Known limitation: shares of drawdowns that are
 * already funded stay with the seller until period end (see docs/09-roadmap-and-limitations.md).
 */
public with sharing class AssignmentService {
    public static Assignment__c settle(Id assignmentId) {
        Assignment__c a = [SELECT Id, Seller_Commitment__c, Buyer__c, Amount__c, Status__c FROM Assignment__c WHERE Id = :assignmentId];
        if (a.Status__c != 'Pending Agent Approval') {
            throw new LoanException('Assignment must be Pending Agent Approval to settle (current status: ' + a.Status__c + ').');
        }
        Lender_Commitment__c seller = [
            SELECT Id, Facility__c, Facility__r.Deal__c, Allocated_Amount__c, Funded_Amount__c, Status__c
            FROM Lender_Commitment__c
            WHERE Id = :a.Seller_Commitment__c
        ];
        Decimal sellerAlloc = LoanMath.nz(seller.Allocated_Amount__c);
        if (a.Amount__c <= 0 || a.Amount__c > sellerAlloc) {
            throw new LoanException('Assignment amount must be positive and not exceed the seller\'s allocated commitment (' + sellerAlloc + ').');
        }
        if (!KycGuard.eligible(new Set<Id>{ a.Buyer__c }).contains(a.Buyer__c)) {
            throw new LoanException('Buyer has not passed current KYC and sanctions checks.');
        }
        Decimal fundedMove = LoanMath.nz(seller.Funded_Amount__c)*(a.Amount__c).divide(sellerAlloc, 2, RoundingMode.HALF_UP);

        List<Lender_Commitment__c> existing = [
            SELECT Id, Allocated_Amount__c, Funded_Amount__c
            FROM Lender_Commitment__c
            WHERE Facility__c = :seller.Facility__c AND Lender__c = :a.Buyer__c
            LIMIT 1
        ];
        Lender_Commitment__c buyer;
        if (existing.isEmpty()) {
            buyer = new Lender_Commitment__c(
                Facility__c = seller.Facility__c, Lender__c = a.Buyer__c, Role__c = 'Participant', Status__c = 'Signed',
                Soft_Commit_Amount__c = a.Amount__c, Allocated_Amount__c = a.Amount__c, Funded_Amount__c = fundedMove
            );
            insert buyer;
        } else {
            buyer = existing[0];
            buyer.Allocated_Amount__c = LoanMath.nz(buyer.Allocated_Amount__c) + a.Amount__c;
            buyer.Funded_Amount__c = LoanMath.nz(buyer.Funded_Amount__c) + fundedMove;
            buyer.Status__c = 'Signed';
            update buyer;
        }
        seller.Allocated_Amount__c = sellerAlloc - a.Amount__c;
        seller.Funded_Amount__c = LoanMath.nz(seller.Funded_Amount__c) - fundedMove;
        if (seller.Allocated_Amount__c == 0) {
            seller.Status__c = 'Withdrawn';
        }
        update seller;

        a.Status__c = 'Settled';
        a.Settlement_Date__c = Date.today();
        update a;
        LoanEvents.publish('ASSIGNMENT_SETTLED', seller.Facility__r.Deal__c, a.Id, new Map<String, Object>{
            'assignmentId' => a.Id, 'sellerCommitmentId' => seller.Id, 'buyerAccountId' => a.Buyer__c, 'amount' => a.Amount__c
        });
        return a;
    }
}
