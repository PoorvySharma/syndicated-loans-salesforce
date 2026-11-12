// Seeds a realistic syndication ready for the Syndication Console:
// USD 100m Term Loan A, three KYC-cleared lenders offering 60m / 50m / 40m (1.5x oversubscribed).
// Run:  sf apex run --file scripts/apex/seed-demo-data.apex
// Then: open the "Syndication Console" tab, pick "Project Atlas (Demo)" and click Allocate.

String suffix = ' (Demo)';
Account borrower = new Account(Name = 'Acme Industries plc' + suffix, Institution_Roles__c = 'Borrower', Country_Code__c = 'GB', Institution_Type__c = 'Corporate');
Account agent    = new Account(Name = 'Agent Bank NA' + suffix, Institution_Roles__c = 'Agent;Lender', Country_Code__c = 'US', Institution_Type__c = 'Commercial Bank');
Account arranger = new Account(Name = 'Arranger Securities' + suffix, Institution_Roles__c = 'Arranger', Country_Code__c = 'GB', Institution_Type__c = 'Investment Bank');
List<Account> lenders = new List<Account>{
    new Account(Name = 'Lender Alpha' + suffix, Institution_Roles__c = 'Lender', Country_Code__c = 'DE', Institution_Type__c = 'Commercial Bank'),
    new Account(Name = 'Lender Beta' + suffix,  Institution_Roles__c = 'Lender', Country_Code__c = 'FR', Institution_Type__c = 'Insurance'),
    new Account(Name = 'Lender Gamma' + suffix, Institution_Roles__c = 'Lender', Country_Code__c = 'US', Institution_Type__c = 'Fund')
};
List<Account> accounts = new List<Account>{ borrower, agent, arranger };
accounts.addAll(lenders);
insert accounts;

List<KYC_Check__c> checks = new List<KYC_Check__c>();
for (Account l : lenders) {
    checks.add(new KYC_Check__c(Account__c = l.Id, Check_Type__c = 'KYC', Status__c = 'Passed', Checked_Date__c = Date.today(), Expiry_Date__c = Date.today().addYears(1)));
    checks.add(new KYC_Check__c(Account__c = l.Id, Check_Type__c = 'Sanctions', Status__c = 'Passed', Checked_Date__c = Date.today(), Expiry_Date__c = Date.today().addYears(1)));
}
insert checks;

Syndicated_Deal__c deal = new Syndicated_Deal__c(
    Name = 'Project Atlas' + suffix, Borrower__c = borrower.Id, Arranger__c = arranger.Id, Agent__c = agent.Id,
    Stage__c = 'Syndication', Currency_Code__c = 'USD', Governing_Law__c = 'English Law',
    Purpose__c = 'Refinancing and general corporate purposes', Mandate_Date__c = Date.today()
);
insert deal;

Facility__c fac = new Facility__c(
    Name = 'Term Loan A', Deal__c = deal.Id, Facility_Type__c = 'Term Loan A', Status__c = 'Open for Commitments',
    Commitment_Amount__c = 100000000, Base_Rate__c = 'SOFR', Margin_Bps__c = 250, Day_Count__c = 'ACT/360',
    Interest_Period_Months__c = 3, Maturity_Date__c = Date.today().addYears(5), Availability_End_Date__c = Date.today().addYears(1)
);
insert fac;

List<Decimal> softs = new List<Decimal>{ 60000000, 50000000, 40000000 };
List<Lender_Commitment__c> lcs = new List<Lender_Commitment__c>();
for (Integer i = 0; i < lenders.size(); i++) {
    lcs.add(new Lender_Commitment__c(Facility__c = fac.Id, Lender__c = lenders[i].Id, Status__c = 'Soft Committed',
        Soft_Commit_Amount__c = softs[i], Role__c = i == 0 ? 'Mandated Lead Arranger' : 'Participant'));
}
insert lcs;

insert new List<Covenant__c>{
    new Covenant__c(Name = 'Maximum leverage', Deal__c = deal.Id, Covenant_Type__c = 'Financial', Metric__c = 'Net Debt / EBITDA', Operator__c = 'Maximum', Threshold__c = 3.5, Test_Frequency__c = 'Quarterly'),
    new Covenant__c(Name = 'Minimum interest cover', Deal__c = deal.Id, Covenant_Type__c = 'Financial', Metric__c = 'Interest Cover', Operator__c = 'Minimum', Threshold__c = 1.5, Test_Frequency__c = 'Quarterly')
};

System.debug('Seeded deal ' + deal.Id + ' with facility ' + fac.Id + ' and ' + lcs.size() + ' soft commitments.');
