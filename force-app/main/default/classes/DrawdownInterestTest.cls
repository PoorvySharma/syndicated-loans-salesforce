@IsTest
private class DrawdownInterestTest {
    private static Drawdown__c notified(TestDataFactory.Scenario s, Decimal amount) {
        Drawdown__c d = DrawdownService.request(s.facility.Id, amount, Date.today());
        return DrawdownService.notifyLenders(d.Id);
    }

    @IsTest
    static void notifySplitsProRataAndReservesAvailability() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c d = notified(s, 30000000);
        Assert.areEqual('Notified', d.Status__c);
        List<Drawdown_Share__c> shares = [SELECT Share_Amount__c FROM Drawdown_Share__c WHERE Drawdown__c = :d.Id];
        Assert.areEqual(3, shares.size());
        Decimal total = 0;
        for (Drawdown_Share__c sh : shares) {
            total += sh.Share_Amount__c;
        }
        Assert.areEqual(30000000, total);
        Facility__c f = TestDataFactory.reload(s.facility.Id);
        Assert.areEqual(30000000, f.Pending_Amount__c);
        Assert.areEqual(70000000, f.Available_Amount__c);
    }

    @IsTest
    static void rejectsWhenAmountExceedsAvailability() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c d = notified(s, 120000000);
        Assert.areEqual('Rejected', d.Status__c);
        Assert.isTrue(d.Rejection_Reason__c.contains('exceeds'));
        Assert.areEqual(0, [SELECT COUNT() FROM Drawdown_Share__c WHERE Drawdown__c = :d.Id]);
    }

    @IsTest
    static void rejectsPastValueDateAndInactiveFacility() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c past = DrawdownService.request(s.facility.Id, 1000000, Date.today().addDays(-1));
        Assert.isTrue(DrawdownService.notifyLenders(past.Id).Rejection_Reason__c.contains('past'));

        TestDataFactory.Scenario s2 = TestDataFactory.syndication();
        Drawdown__c early = DrawdownService.request(s2.facility.Id, 1000000, Date.today());
        Assert.isTrue(DrawdownService.notifyLenders(early.Id).Rejection_Reason__c.contains('not Active'));
    }

    @IsTest
    static void requestValidatesInput() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        try {
            DrawdownService.request(s.facility.Id, 0, Date.today());
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('greater than zero'));
        }
        try {
            DrawdownService.request(s.facility.Id, 1, null);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Value date'));
        }
    }

    @IsTest
    static void fundingUpdatesLenderHoldsAndFacilityDrawn() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c d = notified(s, 30000000);
        try {
            DrawdownService.confirmFunding(d.Id, false);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Not all lender shares'));
        }
        DrawdownService.confirmFunding(d.Id, true);
        Facility__c f = TestDataFactory.reload(s.facility.Id);
        Assert.areEqual(30000000, f.Drawn_Amount__c);
        Assert.areEqual(0, f.Pending_Amount__c);
        Decimal funded = 0;
        for (Lender_Commitment__c lc : [SELECT Funded_Amount__c FROM Lender_Commitment__c WHERE Facility__c = :s.facility.Id]) {
            funded += lc.Funded_Amount__c;
        }
        Assert.areEqual(30000000, funded);

        DrawdownService.repay(d.Id);
        Assert.areEqual(0, TestDataFactory.reload(s.facility.Id).Drawn_Amount__c);
        Assert.areEqual('Repaid', [SELECT Status__c FROM Drawdown__c WHERE Id = :d.Id].Status__c);
    }

    @IsTest
    static void statusGuardsOnDrawdown() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c d = DrawdownService.request(s.facility.Id, 1000000, Date.today());
        try {
            DrawdownService.confirmFunding(d.Id, true);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Notified'));
        }
        try {
            DrawdownService.repay(d.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Funded'));
        }
        DrawdownService.notifyLenders(d.Id);
        try {
            DrawdownService.notifyLenders(d.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Requested'));
        }
    }

    @IsTest
    static void interestLifecycleEndsWithExactDistributions() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Drawdown__c d = notified(s, 30000000);
        try {
            InterestService.openNext(d.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Funded'));
        }
        DrawdownService.confirmFunding(d.Id, true);

        Interest_Period__c p = InterestService.openNext(d.Id);
        Assert.areEqual('Open', p.Status__c);
        Assert.areEqual(Date.today().addMonths(3), p.End_Date__c);
        try {
            InterestService.calculate(p.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('expected Rate Fixed'));
        }
        try {
            InterestService.openNext(d.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('not yet Distributed'));
        }
        try {
            InterestService.fixRate(p.Id, null);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('base rate'));
        }

        InterestService.fixRate(p.Id, 5.0);
        p = InterestService.calculate(p.Id);
        Decimal expected = InterestService.compute(30000000, 5.0, 250, p.Start_Date__c, p.End_Date__c, 'ACT/360');
        Assert.areEqual(expected, p.Interest_Amount__c);
        Assert.isTrue(expected > 0);

        InterestService.markPaid(p.Id);
        List<Payment_Distribution__c> dists = InterestService.distribute(p.Id);
        Assert.areEqual(3, dists.size());
        Decimal paid = 0;
        for (Payment_Distribution__c pd : dists) {
            paid += pd.Amount__c;
        }
        Assert.areEqual(expected, paid, 'distributions must sum to the interest received, to the cent');
        try {
            InterestService.distribute(p.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('expected Paid'));
        }
        Assert.areEqual(3, InterestService.settleDistributions(p.Id, 'PAYRUN-001'));

        // Next period starts where the previous ended.
        Interest_Period__c next = InterestService.openNext(d.Id);
        Assert.areEqual(p.End_Date__c, next.Start_Date__c);
    }
}
