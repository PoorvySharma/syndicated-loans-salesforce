/**
 * Proof that the design works: the complete syndicated-loan lifecycle in one transaction,
 * from bookbuilding to interest distribution, with reconciliation assertions at every step.
 * Mirrors docs/bpmn/01..04 and scripts/apex/run-lifecycle.apex.
 */
@IsTest
private class LifecycleEndToEndTest {
    @IsTest
    static void originationToInterestDistribution() {
        // 1. Origination & bookbuilding: 3 KYC-cleared lenders offer 150m for a 100m facility.
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        Assert.areEqual(1.5, TestDataFactory.reload(s.facility.Id).Oversubscription__c);

        // 2. Allocation: pro-rata cut-back to exactly the facility size.
        SyndicationAllocator.Result alloc = SyndicationAllocator.allocate(s.facility.Id);
        Assert.areEqual(100000000, alloc.totalAllocated);

        // 3. Documentation/CPs satisfied, signing and closing.
        s.deal.CPs_Satisfied__c = true;
        update s.deal;
        ClosingService.close(s.facility.Id);
        Assert.areEqual('Active', TestDataFactory.reload(s.facility.Id).Status__c);

        // 4. Drawdown of 40m: validated, split pro-rata, funded.
        Drawdown__c dd = DrawdownService.request(s.facility.Id, 40000000, Date.today());
        dd = DrawdownService.notifyLenders(dd.Id);
        Assert.areEqual('Notified', dd.Status__c);
        DrawdownService.confirmFunding(dd.Id, true);
        Facility__c f = TestDataFactory.reload(s.facility.Id);
        Assert.areEqual(40000000, f.Drawn_Amount__c);
        Assert.areEqual(60000000, f.Available_Amount__c);

        // 5. Interest: fix SOFR, calculate, borrower pays, agent distributes.
        Interest_Period__c p = InterestService.openNext(dd.Id);
        InterestService.fixRate(p.Id, 4.30);
        p = InterestService.calculate(p.Id);
        Decimal expected = InterestService.compute(40000000, 4.30, 250, p.Start_Date__c, p.End_Date__c, 'ACT/360');
        Assert.areEqual(expected, p.Interest_Amount__c);
        InterestService.markPaid(p.Id);
        List<Payment_Distribution__c> dists = InterestService.distribute(p.Id);
        Decimal distributed = 0;
        for (Payment_Distribution__c d : dists) {
            distributed += d.Amount__c;
        }
        Assert.areEqual(expected, distributed, 'agent must pass on every cent received');
        Assert.areEqual('Distributed', [SELECT Status__c FROM Interest_Period__c WHERE Id = :p.Id].Status__c);

        // 6. Lender holds reconcile: sum of funded holds equals facility drawn amount.
        Decimal funded = 0;
        for (Lender_Commitment__c lc : [SELECT Funded_Amount__c FROM Lender_Commitment__c WHERE Facility__c = :s.facility.Id]) {
            funded += lc.Funded_Amount__c;
        }
        Assert.areEqual(f.Drawn_Amount__c, funded);

        // 7. Lender consent to a waiver under a super-majority vote.
        Amendment_Request__c am = new Amendment_Request__c(Deal__c = s.deal.Id, Amendment_Type__c = 'Waiver', Required_Majority_Pct__c = 66.67);
        insert am;
        ConsentService.circulate(am.Id);
        List<Lender_Consent__c> votes = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :am.Id ORDER BY Weight_Amount__c DESC];
        votes[0].Response__c = 'Consent';
        votes[1].Response__c = 'Consent';
        update new List<Lender_Consent__c>{ votes[0], votes[1] };
        Assert.areEqual('Approved', [SELECT Status__c FROM Amendment_Request__c WHERE Id = :am.Id].Status__c);

        // 8. Repayment of the drawdown.
        DrawdownService.repay(dd.Id);
        Assert.areEqual(0, TestDataFactory.reload(s.facility.Id).Drawn_Amount__c);
        Assert.areEqual(100000000, TestDataFactory.reload(s.facility.Id).Available_Amount__c);
    }
}
