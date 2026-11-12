/**
 * Backend for the syndicationConsole LWC. Reads run in USER_MODE (FLS + sharing enforced);
 * actions additionally require the Syndication_Operate custom permission.
 */
public with sharing class SyndicationConsoleController {
    @AuraEnabled(cacheable=true)
    public static List<Syndicated_Deal__c> getDeals() {
        return [SELECT Id, Name, Stage__c FROM Syndicated_Deal__c WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 100];
    }

    @AuraEnabled
    public static Map<String, Object> getBoard(Id dealId) {
        Syndicated_Deal__c deal = [
            SELECT Id, Name, Stage__c, Currency_Code__c, Total_Commitment__c, CPs_Satisfied__c, Borrower__r.Name, Agent__r.Name
            FROM Syndicated_Deal__c
            WHERE Id = :dealId
            WITH USER_MODE
        ];
        List<Facility__c> facilities = [
            SELECT Id, Name, Facility_Type__c, Status__c, Commitment_Amount__c, Soft_Commit_Total__c, Allocated_Amount__c,
                   Drawn_Amount__c, Pending_Amount__c, Available_Amount__c, Oversubscription__c, Margin_Bps__c, Day_Count__c,
                   (SELECT Id, Name, Lender__r.Name, Status__c, Soft_Commit_Amount__c, Allocated_Amount__c, Funded_Amount__c, Share_Pct__c
                    FROM Lender_Commitments__r ORDER BY CreatedDate, Id),
                   (SELECT Id, Name, Amount__c, Value_Date__c, Status__c, Rejection_Reason__c,
                           (SELECT Id, Name, Start_Date__c, End_Date__c, Principal_Amount__c, Base_Rate_Pct__c, All_In_Rate_Pct__c, Interest_Amount__c, Status__c
                            FROM Interest_Periods__r ORDER BY Start_Date__c)
                    FROM Drawdowns__r ORDER BY CreatedDate, Id)
            FROM Facility__c
            WHERE Deal__c = :dealId
            WITH USER_MODE
            ORDER BY CreatedDate, Id
        ];
        return new Map<String, Object>{ 'deal' => deal, 'facilities' => facilities };
    }

    /** Single dispatch point for every console action; returns a user-facing confirmation message. */
    @AuraEnabled
    public static String perform(String action, Id recordId, Decimal numberArg, Date dateArg) {
        String msg;
        try {
            SyndicationSecurity.requireOperator();
            switch on action {
                when 'ALLOCATE' {
                    SyndicationAllocator.Result r = SyndicationAllocator.allocate(recordId);
                    msg = 'Allocated ' + r.totalAllocated + ' of ' + r.commitment
                        + (r.oversubscribed ? ' (cut back to ' + r.cutBackPct + '% of soft commitments)' : '')
                        + (r.blocked.isEmpty() ? '' : '. Blocked by KYC/sanctions: ' + String.join(r.blocked, ', '));
                }
                when 'CLOSE_FACILITY' {
                    ClosingService.close(recordId);
                    msg = 'Facility closed: commitments signed and facility active.';
                }
                when 'REQUEST_DRAWDOWN' {
                    Drawdown__c d = DrawdownService.request(recordId, numberArg, dateArg);
                    msg = 'Drawdown ' + [SELECT Name FROM Drawdown__c WHERE Id = :d.Id].Name + ' requested.';
                }
                when 'NOTIFY_DRAWDOWN' {
                    Drawdown__c d = DrawdownService.notifyLenders(recordId);
                    msg = d.Status__c == 'Rejected' ? 'Drawdown rejected: ' + d.Rejection_Reason__c : 'Lenders notified of their pro-rata shares.';
                }
                when 'FUND_DRAWDOWN' {
                    DrawdownService.confirmFunding(recordId, true);
                    msg = 'Funding confirmed (all shares marked funded).';
                }
                when 'REPAY_DRAWDOWN' {
                    DrawdownService.repay(recordId);
                    msg = 'Drawdown repaid.';
                }
                when 'OPEN_PERIOD' {
                    Interest_Period__c p = InterestService.openNext(recordId);
                    msg = 'Interest period opened: ' + p.Start_Date__c.format() + ' to ' + p.End_Date__c.format() + '.';
                }
                when 'FIX_RATE' {
                    InterestService.fixRate(recordId, numberArg);
                    msg = 'Base rate fixed at ' + numberArg + '%.';
                }
                when 'CALC_INTEREST' {
                    Interest_Period__c p = InterestService.calculate(recordId);
                    msg = 'Interest calculated: ' + p.Interest_Amount__c;
                }
                when 'MARK_PAID' {
                    InterestService.markPaid(recordId);
                    msg = 'Borrower payment recorded.';
                }
                when 'DISTRIBUTE' {
                    List<Payment_Distribution__c> ds = InterestService.distribute(recordId);
                    msg = 'Interest distributed to ' + ds.size() + ' lenders.';
                }
                when else {
                    throw new LoanException('Unknown action: ' + action);
                }
            }
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
        return msg;
    }
}
