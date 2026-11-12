@IsTest
private class GovernanceTest {
    private static Amendment_Request__c draft(Id dealId, Decimal majority) {
        Amendment_Request__c a = new Amendment_Request__c(Deal__c = dealId, Amendment_Type__c = 'Waiver', Required_Majority_Pct__c = majority, Response_Deadline__c = Date.today().addDays(10));
        insert a;
        return a;
    }

    @IsTest
    static void superMajorityApprovesAndRecordsPercentages() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Amendment_Request__c a = draft(s.deal.Id, 66.67);
        Assert.areEqual(3, ConsentService.circulate(a.Id));

        List<Lender_Consent__c> cs = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :a.Id ORDER BY Weight_Amount__c DESC];
        cs[0].Response__c = 'Consent';
        update cs[0];
        a = [SELECT Status__c, Consent_Pct__c FROM Amendment_Request__c WHERE Id = :a.Id];
        Assert.areEqual('Circulated', a.Status__c);
        Assert.areEqual(40, a.Consent_Pct__c.setScale(0, RoundingMode.HALF_UP));

        cs[1].Response__c = 'Consent';
        update cs[1];
        a = [SELECT Status__c, Resolution_Date__c FROM Amendment_Request__c WHERE Id = :a.Id];
        Assert.areEqual('Approved', a.Status__c);
        Assert.areEqual(Date.today(), a.Resolution_Date__c);
        Assert.areEqual(Date.today(), [SELECT Responded_Date__c FROM Lender_Consent__c WHERE Id = :cs[0].Id].Responded_Date__c);
    }

    @IsTest
    static void amendmentRejectedAsSoonAsThresholdIsUnreachable() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Amendment_Request__c a = draft(s.deal.Id, 66.67);
        ConsentService.circulate(a.Id);
        Lender_Consent__c biggest = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :a.Id ORDER BY Weight_Amount__c DESC LIMIT 1];
        biggest.Response__c = 'Decline';
        update biggest;
        Assert.areEqual('Rejected', [SELECT Status__c FROM Amendment_Request__c WHERE Id = :a.Id].Status__c);
    }

    @IsTest
    static void unanimousMattersNeedEveryLender() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Amendment_Request__c a = draft(s.deal.Id, 100);
        ConsentService.circulate(a.Id);
        List<Lender_Consent__c> cs = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :a.Id];
        for (Lender_Consent__c c : cs) {
            c.Response__c = 'Consent';
        }
        update cs;
        Assert.areEqual('Approved', [SELECT Status__c FROM Amendment_Request__c WHERE Id = :a.Id].Status__c);
    }

    @IsTest
    static void expiredWhenDeadlinePassesWithoutDecision() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Amendment_Request__c a = draft(s.deal.Id, 66.67);
        ConsentService.circulate(a.Id);
        a.Response_Deadline__c = Date.today().addDays(-1);
        update a;
        Lender_Consent__c small = [SELECT Id FROM Lender_Consent__c WHERE Amendment__c = :a.Id ORDER BY Weight_Amount__c ASC LIMIT 1];
        small.Response__c = 'Consent';
        update small;
        Assert.areEqual('Expired', [SELECT Status__c FROM Amendment_Request__c WHERE Id = :a.Id].Status__c);
    }

    @IsTest
    static void circulateGuards() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Amendment_Request__c a = draft(s.deal.Id, 66.67);
        ConsentService.circulate(a.Id);
        try {
            ConsentService.circulate(a.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Draft'));
        }
        TestDataFactory.Scenario open = TestDataFactory.syndication();
        Amendment_Request__c b = draft(open.deal.Id, 66.67);
        try {
            ConsentService.circulate(b.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('no signed lenders'));
        }
    }

    @IsTest
    static void covenantTestsDeriveResultAndRollStatus() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Covenant__c leverage = new Covenant__c(Name = 'Max leverage', Deal__c = s.deal.Id, Covenant_Type__c = 'Financial', Metric__c = 'Net Debt / EBITDA', Operator__c = 'Maximum', Threshold__c = 3.5);
        Covenant__c cover = new Covenant__c(Name = 'Min interest cover', Deal__c = s.deal.Id, Covenant_Type__c = 'Financial', Metric__c = 'Interest Cover', Operator__c = 'Minimum', Threshold__c = 1.5);
        insert new List<Covenant__c>{ leverage, cover };

        insert new Covenant_Test__c(Covenant__c = leverage.Id, Test_Date__c = Date.today().addMonths(-3), Actual_Value__c = 3.0);
        Assert.areEqual('Compliant', [SELECT Status__c FROM Covenant__c WHERE Id = :leverage.Id].Status__c);

        insert new Covenant_Test__c(Covenant__c = leverage.Id, Test_Date__c = Date.today(), Actual_Value__c = 4.2);
        Assert.areEqual('Breached', [SELECT Status__c FROM Covenant__c WHERE Id = :leverage.Id].Status__c);
        Assert.areEqual('Breach', [SELECT Result__c FROM Covenant_Test__c WHERE Covenant__c = :leverage.Id AND Actual_Value__c = 4.2].Result__c);

        insert new Covenant_Test__c(Covenant__c = cover.Id, Test_Date__c = Date.today(), Actual_Value__c = 1.0);
        Assert.areEqual('Breached', [SELECT Status__c FROM Covenant__c WHERE Id = :cover.Id].Status__c);

        // A lender-approved waiver is recorded manually and is not overwritten by the evaluator.
        insert new Covenant_Test__c(Covenant__c = cover.Id, Test_Date__c = Date.today().addDays(1), Actual_Value__c = 1.0, Result__c = 'Waived');
        Assert.areEqual('Waived', [SELECT Status__c FROM Covenant__c WHERE Id = :cover.Id].Status__c);
    }

    @IsTest
    static void assignmentMovesCommitmentToCompliantBuyer() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Account buyer = TestDataFactory.institution('Lender Delta', 'Lender');
        TestDataFactory.passCompliance(buyer.Id);
        Lender_Commitment__c seller = TestDataFactory.commitmentFor(s.lenders[2].Id);
        Decimal before = seller.Allocated_Amount__c;

        Assignment__c a = new Assignment__c(Seller_Commitment__c = seller.Id, Buyer__c = buyer.Id, Amount__c = 10000000, Status__c = 'Pending Agent Approval');
        insert a;
        AssignmentService.settle(a.Id);

        Assert.areEqual(before - 10000000, TestDataFactory.commitmentFor(s.lenders[2].Id).Allocated_Amount__c);
        Lender_Commitment__c bought = TestDataFactory.commitmentFor(buyer.Id);
        Assert.areEqual(10000000, bought.Allocated_Amount__c);
        Assert.areEqual('Signed', bought.Status__c);
        Assert.areEqual(100000000, TestDataFactory.reload(s.facility.Id).Allocated_Amount__c, 'facility total is unchanged by a transfer');
        Assert.areEqual('Settled', [SELECT Status__c FROM Assignment__c WHERE Id = :a.Id].Status__c);

        // A second partial assignment tops up the buyer's existing commitment.
        Assignment__c a2 = new Assignment__c(Seller_Commitment__c = seller.Id, Buyer__c = buyer.Id, Amount__c = 5000000, Status__c = 'Pending Agent Approval');
        insert a2;
        AssignmentService.settle(a2.Id);
        Assert.areEqual(15000000, TestDataFactory.commitmentFor(buyer.Id).Allocated_Amount__c);
    }

    @IsTest
    static void assignmentGuards() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Account noKyc = TestDataFactory.institution('Shady Capital', 'Lender');
        Lender_Commitment__c seller = TestDataFactory.commitmentFor(s.lenders[2].Id);

        Assignment__c wrongStatus = new Assignment__c(Seller_Commitment__c = seller.Id, Buyer__c = noKyc.Id, Amount__c = 1000000, Status__c = 'Proposed');
        Assignment__c noKycAssign = new Assignment__c(Seller_Commitment__c = seller.Id, Buyer__c = noKyc.Id, Amount__c = 1000000, Status__c = 'Pending Agent Approval');
        Assignment__c tooBig = new Assignment__c(Seller_Commitment__c = seller.Id, Buyer__c = noKyc.Id, Amount__c = 999000000, Status__c = 'Pending Agent Approval');
        insert new List<Assignment__c>{ wrongStatus, noKycAssign, tooBig };

        Map<Id, String> expected = new Map<Id, String>{ wrongStatus.Id => 'Pending Agent Approval', noKycAssign.Id => 'KYC', tooBig.Id => 'not exceed' };
        for (Id aid : expected.keySet()) {
            try {
                AssignmentService.settle(aid);
                Assert.fail('expected exception for ' + aid);
            } catch (LoanException e) {
                Assert.isTrue(e.getMessage().contains(expected.get(aid)), e.getMessage());
            }
        }
    }
}
