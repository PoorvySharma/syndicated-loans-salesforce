/**
 * Drawdown lifecycle: request -> validate & notify (pro-rata shares) -> fund -> (repay).
 */
public with sharing class DrawdownService {
    public static Drawdown__c request(Id facilityId, Decimal amount, Date valueDate) {
        if (amount == null || amount <= 0) {
            throw new LoanException('Drawdown amount must be greater than zero.');
        }
        if (valueDate == null) {
            throw new LoanException('Value date is required.');
        }
        Drawdown__c d = new Drawdown__c(
            Facility__c = facilityId,
            Amount__c = amount,
            Value_Date__c = valueDate,
            Request_Date__c = Date.today(),
            Status__c = 'Requested'
        );
        insert d;
        return d;
    }

    /** Agent validation + lender notification. Rejects (with reason) instead of throwing on business-rule failures. */
    public static Drawdown__c notifyLenders(Id drawdownId) {
        Drawdown__c d = [SELECT Id, Facility__c, Amount__c, Value_Date__c, Status__c, Rejection_Reason__c FROM Drawdown__c WHERE Id = :drawdownId];
        if (d.Status__c != 'Requested') {
            throw new LoanException('Only Requested drawdowns can be notified (current status: ' + d.Status__c + ').');
        }
        Facility__c f = [
            SELECT Id, Deal__c, Status__c, Maturity_Date__c, Availability_End_Date__c, Available_Amount__c
            FROM Facility__c
            WHERE Id = :d.Facility__c
        ];
        List<Lender_Commitment__c> holders = [
            SELECT Id, Allocated_Amount__c
            FROM Lender_Commitment__c
            WHERE Facility__c = :f.Id AND Status__c = 'Signed' AND Allocated_Amount__c > 0
            ORDER BY CreatedDate, Id
        ];
        String reason = validate(d, f, holders);
        if (reason != null) {
            d.Status__c = 'Rejected';
            d.Rejection_Reason__c = reason.left(255);
            update d;
            LoanEvents.publish('DRAWDOWN_REJECTED', f.Deal__c, d.Id, new Map<String, Object>{ 'drawdownId' => d.Id, 'reason' => reason });
            return d;
        }

        List<Decimal> weights = new List<Decimal>();
        for (Lender_Commitment__c h : holders) {
            weights.add(h.Allocated_Amount__c);
        }
        List<Decimal> parts = LoanMath.split(d.Amount__c, weights);
        List<Drawdown_Share__c> shares = new List<Drawdown_Share__c>();
        List<Map<String, Object>> shareView = new List<Map<String, Object>>();
        for (Integer i = 0; i < holders.size(); i++) {
            if (parts[i] > 0) {
                shares.add(new Drawdown_Share__c(Drawdown__c = d.Id, Lender_Commitment__c = holders[i].Id, Share_Amount__c = parts[i], Status__c = 'Notified'));
                shareView.add(new Map<String, Object>{ 'commitmentId' => holders[i].Id, 'amount' => parts[i] });
            }
        }
        insert shares;
        d.Status__c = 'Notified';
        update d;
        LoanEvents.publish(
            'DRAWDOWN_NOTIFIED',
            f.Deal__c,
            d.Id,
            new Map<String, Object>{
                'drawdownId' => d.Id,
                'amount' => d.Amount__c,
                'valueDate' => String.valueOf(d.Value_Date__c),
                'shares' => shareView
            }
        );
        return d;
    }

    /**
     * Agent confirms lender funds received and disbursed to the borrower.
     * autoFundShares=true marks outstanding shares funded (demo / test convenience; production integrates with payments).
     */
    public static Drawdown__c confirmFunding(Id drawdownId, Boolean autoFundShares) {
        Drawdown__c d = [SELECT Id, Facility__r.Deal__c, Amount__c, Status__c FROM Drawdown__c WHERE Id = :drawdownId];
        if (d.Status__c != 'Notified') {
            throw new LoanException('Only Notified drawdowns can be funded (current status: ' + d.Status__c + ').');
        }
        List<Drawdown_Share__c> shares = [SELECT Id, Lender_Commitment__c, Share_Amount__c, Status__c FROM Drawdown_Share__c WHERE Drawdown__c = :d.Id];
        List<Drawdown_Share__c> changed = new List<Drawdown_Share__c>();
        for (Drawdown_Share__c s : shares) {
            if (s.Status__c != 'Funded') {
                if (autoFundShares != true) {
                    throw new LoanException('Not all lender shares are funded yet.');
                }
                s.Status__c = 'Funded';
                s.Funded_Date__c = Date.today();
                changed.add(s);
            }
        }
        update changed;
        adjustFunded(shares, 1);
        d.Status__c = 'Funded';
        d.Funded_Date__c = Date.today();
        update d;
        LoanEvents.publish('DRAWDOWN_FUNDED', d.Facility__r.Deal__c, d.Id, new Map<String, Object>{ 'drawdownId' => d.Id, 'amount' => d.Amount__c });
        return d;
    }

    public static Drawdown__c repay(Id drawdownId) {
        Drawdown__c d = [SELECT Id, Facility__r.Deal__c, Amount__c, Status__c FROM Drawdown__c WHERE Id = :drawdownId];
        if (d.Status__c != 'Funded') {
            throw new LoanException('Only Funded drawdowns can be repaid (current status: ' + d.Status__c + ').');
        }
        List<Drawdown_Share__c> shares = [SELECT Id, Lender_Commitment__c, Share_Amount__c FROM Drawdown_Share__c WHERE Drawdown__c = :d.Id AND Status__c = 'Funded'];
        adjustFunded(shares, -1);
        d.Status__c = 'Repaid';
        d.Repayment_Date__c = Date.today();
        update d;
        LoanEvents.publish('DRAWDOWN_REPAID', d.Facility__r.Deal__c, d.Id, new Map<String, Object>{ 'drawdownId' => d.Id, 'amount' => d.Amount__c });
        return d;
    }

    private static String validate(Drawdown__c d, Facility__c f, List<Lender_Commitment__c> holders) {
        if (f.Status__c != 'Active') {
            return 'Facility is not Active (status: ' + f.Status__c + ').';
        }
        if (d.Value_Date__c < Date.today()) {
            return 'Value date is in the past.';
        }
        if (d.Value_Date__c > f.Maturity_Date__c) {
            return 'Value date is after the facility maturity.';
        }
        if (f.Availability_End_Date__c != null && d.Value_Date__c > f.Availability_End_Date__c) {
            return 'Value date is after the end of the availability period.';
        }
        if (d.Amount__c > LoanMath.nz(f.Available_Amount__c)) {
            return 'Amount exceeds the available commitment (' + LoanMath.nz(f.Available_Amount__c) + ').';
        }
        if (holders.isEmpty()) {
            return 'The facility has no signed lender commitments.';
        }
        return null;
    }

    private static void adjustFunded(List<Drawdown_Share__c> shares, Integer sign) {
        Set<Id> ids = new Set<Id>();
        for (Drawdown_Share__c s : shares) {
            ids.add(s.Lender_Commitment__c);
        }
        Map<Id, Lender_Commitment__c> lcs = new Map<Id, Lender_Commitment__c>(
            [SELECT Id, Funded_Amount__c FROM Lender_Commitment__c WHERE Id IN :ids]
        );
        for (Drawdown_Share__c s : shares) {
            Lender_Commitment__c lc = lcs.get(s.Lender_Commitment__c);
            lc.Funded_Amount__c = LoanMath.nz(lc.Funded_Amount__c) + sign * LoanMath.nz(s.Share_Amount__c);
        }
        update lcs.values();
    }
}
