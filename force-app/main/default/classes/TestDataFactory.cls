/** Builds a realistic syndication: 3 lenders, USD 100m facility, USD 150m soft commitments (1.5x oversubscribed). */
@IsTest
public class TestDataFactory {
    public class Scenario {
        public Account borrower;
        public Account agent;
        public Account arranger;
        public List<Account> lenders = new List<Account>();
        public Syndicated_Deal__c deal;
        public Facility__c facility;
        public List<Lender_Commitment__c> commitments = new List<Lender_Commitment__c>();
    }

    public static Account institution(String name, String roles) {
        Account a = new Account(Name = name, Institution_Roles__c = roles, Country_Code__c = 'GB');
        insert a;
        return a;
    }

    public static void passCompliance(Id accountId) {
        insert new List<KYC_Check__c>{
            new KYC_Check__c(Account__c = accountId, Check_Type__c = 'KYC', Status__c = 'Passed', Checked_Date__c = Date.today(), Expiry_Date__c = Date.today().addYears(1)),
            new KYC_Check__c(Account__c = accountId, Check_Type__c = 'Sanctions', Status__c = 'Passed', Checked_Date__c = Date.today(), Expiry_Date__c = Date.today().addYears(1))
        };
    }

    /** Deal + facility + 3 KYC-cleared lenders with soft commitments 60m / 50m / 40m. */
    public static Scenario syndication() {
        Scenario s = new Scenario();
        s.borrower = institution('Acme Industries plc', 'Borrower');
        s.agent = institution('Agent Bank NA', 'Agent');
        s.arranger = institution('Arranger Securities', 'Arranger');
        s.deal = new Syndicated_Deal__c(
            Name = 'Project Atlas', Borrower__c = s.borrower.Id, Arranger__c = s.arranger.Id, Agent__c = s.agent.Id,
            Stage__c = 'Syndication', Currency_Code__c = 'USD', Mandate_Date__c = Date.today()
        );
        insert s.deal;
        s.facility = new Facility__c(
            Name = 'Term Loan A', Deal__c = s.deal.Id, Facility_Type__c = 'Term Loan A', Status__c = 'Open for Commitments',
            Commitment_Amount__c = 100000000, Base_Rate__c = 'SOFR', Margin_Bps__c = 250, Day_Count__c = 'ACT/360',
            Interest_Period_Months__c = 3, Maturity_Date__c = Date.today().addYears(5)
        );
        insert s.facility;
        List<String> names = new List<String>{ 'Lender Alpha', 'Lender Beta', 'Lender Gamma' };
        List<Decimal> softs = new List<Decimal>{ 60000000, 50000000, 40000000 };
        for (Integer i = 0; i < names.size(); i++) {
            Account l = institution(names[i], 'Lender');
            passCompliance(l.Id);
            s.lenders.add(l);
            Lender_Commitment__c lc = new Lender_Commitment__c(
                Facility__c = s.facility.Id, Lender__c = l.Id, Status__c = 'Soft Committed', Soft_Commit_Amount__c = softs[i]
            );
            insert lc;
            s.commitments.add(lc);
        }
        return s;
    }

    /** Syndication carried through allocation, CP confirmation and closing. */
    public static Scenario activeFacility() {
        Scenario s = syndication();
        SyndicationAllocator.allocate(s.facility.Id);
        s.deal.CPs_Satisfied__c = true;
        update s.deal;
        ClosingService.close(s.facility.Id);
        return s;
    }

    public static Lender_Commitment__c commitmentFor(Id lenderAccountId) {
        return [SELECT Id, Allocated_Amount__c, Funded_Amount__c, Status__c FROM Lender_Commitment__c WHERE Lender__c = :lenderAccountId LIMIT 1];
    }

    public static Facility__c reload(Id facilityId) {
        return [
            SELECT Id, Status__c, Commitment_Amount__c, Soft_Commit_Total__c, Allocated_Amount__c, Drawn_Amount__c, Pending_Amount__c, Available_Amount__c, Oversubscription__c
            FROM Facility__c WHERE Id = :facilityId
        ];
    }

    public static Decimal sum(List<Decimal> values) {
        Decimal t = 0;
        for (Decimal v : values) {
            t += v;
        }
        return t;
    }
}
