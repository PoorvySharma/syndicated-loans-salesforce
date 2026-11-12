// Runs the complete syndicated-loan lifecycle and prints a reconciliation to the debug log.
// Mirrors force-app/.../LifecycleEndToEndTest and docs/bpmn/01..04.
// Run:  sf apex run --file scripts/apex/run-lifecycle.apex
// Creates records tagged "(Lifecycle)" in the target org (use a scratch org or sandbox).

String tag = ' (Lifecycle)';
Account borrower = new Account(Name = 'Borrower Co' + tag, Institution_Roles__c = 'Borrower');
Account agent = new Account(Name = 'Agent Bank' + tag, Institution_Roles__c = 'Agent');
List<Account> lenders = new List<Account>{
    new Account(Name = 'Lender A' + tag, Institution_Roles__c = 'Lender'),
    new Account(Name = 'Lender B' + tag, Institution_Roles__c = 'Lender'),
    new Account(Name = 'Lender C' + tag, Institution_Roles__c = 'Lender')
};
List<Account> accs = new List<Account>{ borrower, agent };
accs.addAll(lenders);
insert accs;
List<KYC_Check__c> kyc = new List<KYC_Check__c>();
for (Account l : lenders) {
    kyc.add(new KYC_Check__c(Account__c = l.Id, Check_Type__c = 'KYC', Status__c = 'Passed', Expiry_Date__c = Date.today().addYears(1)));
    kyc.add(new KYC_Check__c(Account__c = l.Id, Check_Type__c = 'Sanctions', Status__c = 'Passed', Expiry_Date__c = Date.today().addYears(1)));
}
insert kyc;

Syndicated_Deal__c deal = new Syndicated_Deal__c(Name = 'Lifecycle deal' + tag, Borrower__c = borrower.Id, Agent__c = agent.Id, Stage__c = 'Syndication', Currency_Code__c = 'USD');
insert deal;
Facility__c fac = new Facility__c(Name = 'Term Loan A', Deal__c = deal.Id, Facility_Type__c = 'Term Loan A', Status__c = 'Open for Commitments',
    Commitment_Amount__c = 100000000, Base_Rate__c = 'SOFR', Margin_Bps__c = 250, Day_Count__c = 'ACT/360',
    Interest_Period_Months__c = 3, Maturity_Date__c = Date.today().addYears(5));
insert fac;
List<Decimal> softs = new List<Decimal>{ 60000000, 50000000, 40000000 };
List<Lender_Commitment__c> lcs = new List<Lender_Commitment__c>();
for (Integer i = 0; i < 3; i++) {
    lcs.add(new Lender_Commitment__c(Facility__c = fac.Id, Lender__c = lenders[i].Id, Status__c = 'Soft Committed', Soft_Commit_Amount__c = softs[i]));
}
insert lcs;

System.debug('=== 1. ALLOCATION ===');
SyndicationAllocator.Result alloc = SyndicationAllocator.allocate(fac.Id);
System.debug('Soft ' + alloc.totalSoftCommit + ' -> allocated ' + alloc.totalAllocated + ' (cut-back ' + alloc.cutBackPct + '%)');
for (SyndicationAllocator.Line l : alloc.lines) {
    System.debug('  ' + l.lender + ': soft ' + l.softCommit + ' -> allocated ' + l.allocated);
}

System.debug('=== 2. CLOSING ===');
deal.CPs_Satisfied__c = true;
update deal;
ClosingService.close(fac.Id);
System.debug('Facility status: ' + [SELECT Status__c FROM Facility__c WHERE Id = :fac.Id].Status__c);

System.debug('=== 3. DRAWDOWN 40m ===');
Drawdown__c dd = DrawdownService.request(fac.Id, 40000000, Date.today());
dd = DrawdownService.notifyLenders(dd.Id);
System.debug('Drawdown status: ' + dd.Status__c);
for (Drawdown_Share__c s : [SELECT Lender_Name__c, Share_Amount__c FROM Drawdown_Share__c WHERE Drawdown__c = :dd.Id ORDER BY Share_Amount__c DESC]) {
    System.debug('  ' + s.Lender_Name__c + ' funds ' + s.Share_Amount__c);
}
DrawdownService.confirmFunding(dd.Id, true);
Facility__c f = [SELECT Drawn_Amount__c, Available_Amount__c FROM Facility__c WHERE Id = :fac.Id];
System.debug('Drawn ' + f.Drawn_Amount__c + ', available ' + f.Available_Amount__c);

System.debug('=== 4. INTEREST ===');
Interest_Period__c p = InterestService.openNext(dd.Id);
InterestService.fixRate(p.Id, 4.30);
p = InterestService.calculate(p.Id);
System.debug('Period ' + p.Start_Date__c + ' to ' + p.End_Date__c + ': interest ' + p.Interest_Amount__c);
InterestService.markPaid(p.Id);
Decimal distributed = 0;
for (Payment_Distribution__c d : InterestService.distribute(p.Id)) {
    distributed += d.Amount__c;
}
System.debug('Distributed ' + distributed + ' (must equal ' + p.Interest_Amount__c + ')');

System.debug('=== 5. WAIVER VOTE ===');
Amendment_Request__c am = new Amendment_Request__c(Deal__c = deal.Id, Amendment_Type__c = 'Waiver', Required_Majority_Pct__c = 66.67);
insert am;
ConsentService.circulate(am.Id);
List<Lender_Consent__c> votes = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :am.Id ORDER BY Weight_Amount__c DESC];
votes[0].Response__c = 'Consent';
votes[1].Response__c = 'Consent';
update new List<Lender_Consent__c>{ votes[0], votes[1] };
Amendment_Request__c res = [SELECT Status__c, Consent_Pct__c FROM Amendment_Request__c WHERE Id = :am.Id];
System.debug('Amendment: ' + res.Status__c + ' with ' + res.Consent_Pct__c + '% consent');

System.debug('=== 6. RECONCILIATION ===');
Decimal funded = 0;
for (Lender_Commitment__c lc : [SELECT Funded_Amount__c FROM Lender_Commitment__c WHERE Facility__c = :fac.Id]) {
    funded += lc.Funded_Amount__c;
}
System.assertEquals(f.Drawn_Amount__c, funded, 'Sum of lender funded holds must equal facility drawn amount');
System.assertEquals(p.Interest_Amount__c, distributed, 'Distributions must equal interest received');
System.assertEquals('Approved', res.Status__c);
System.debug('ALL RECONCILIATION CHECKS PASSED');
