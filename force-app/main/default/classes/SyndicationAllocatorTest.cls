@IsTest
private class SyndicationAllocatorTest {
    @IsTest
    static void oversubscribedBookIsCutBackProRata() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        SyndicationAllocator.Result r = SyndicationAllocator.allocate(s.facility.Id);

        Assert.isTrue(r.oversubscribed);
        Assert.isTrue(r.fullyAllocated);
        Assert.areEqual(150000000, r.totalSoftCommit);
        Assert.areEqual(100000000, r.totalAllocated);
        Assert.areEqual(66.67, r.cutBackPct);
        Assert.areEqual(3, r.lines.size());

        Facility__c f = TestDataFactory.reload(s.facility.Id);
        Assert.areEqual('Allocated', f.Status__c);
        Assert.areEqual(100000000, f.Allocated_Amount__c);
        Assert.areEqual(1.5, f.Oversubscription__c);
        for (Lender_Commitment__c lc : [SELECT Allocated_Amount__c, Soft_Commit_Amount__c, Status__c FROM Lender_Commitment__c WHERE Facility__c = :s.facility.Id]) {
            Assert.areEqual('Allocated', lc.Status__c);
            Assert.isTrue(lc.Allocated_Amount__c <= lc.Soft_Commit_Amount__c);
        }
    }

    @IsTest
    static void lenderWithoutCurrentKycIsBlocked() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        delete [SELECT Id FROM KYC_Check__c WHERE Account__c = :s.lenders[2].Id];

        SyndicationAllocator.Result r = SyndicationAllocator.allocate(s.facility.Id);
        Assert.areEqual(1, r.blocked.size());
        Assert.areEqual('Lender Gamma', r.blocked[0]);
        Assert.areEqual(110000000, r.totalSoftCommit);
        Lender_Commitment__c gamma = TestDataFactory.commitmentFor(s.lenders[2].Id);
        Assert.areEqual('Soft Committed', gamma.Status__c);
        Assert.areEqual(0, gamma.Allocated_Amount__c);
    }

    @IsTest
    static void expiredKycBlocksLender() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        List<KYC_Check__c> checks = [SELECT Id FROM KYC_Check__c WHERE Account__c = :s.lenders[0].Id];
        for (KYC_Check__c c : checks) {
            c.Expiry_Date__c = Date.today().addDays(-1);
        }
        update checks;
        Assert.areEqual(1, SyndicationAllocator.allocate(s.facility.Id).blocked.size());
    }

    @IsTest
    static void undersubscribedBookAllocatesInFullButStaysOpen() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        for (Lender_Commitment__c lc : s.commitments) {
            lc.Soft_Commit_Amount__c = 10000000;
        }
        update s.commitments;
        SyndicationAllocator.Result r = SyndicationAllocator.allocate(s.facility.Id);
        Assert.isFalse(r.oversubscribed);
        Assert.isFalse(r.fullyAllocated);
        Assert.areEqual(30000000, r.totalAllocated);
        Assert.areEqual('Open for Commitments', TestDataFactory.reload(s.facility.Id).Status__c);
    }

    @IsTest
    static void rerunAfterWithdrawalReallocates() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        SyndicationAllocator.allocate(s.facility.Id);
        Lender_Commitment__c alpha = TestDataFactory.commitmentFor(s.lenders[0].Id);
        alpha.Status__c = 'Withdrawn';
        update alpha;
        SyndicationAllocator.Result r = SyndicationAllocator.allocate(s.facility.Id);
        Assert.areEqual(90000000, r.totalSoftCommit);
        Assert.isFalse(r.oversubscribed);
        Assert.areEqual(0, TestDataFactory.commitmentFor(s.lenders[0].Id).Allocated_Amount__c);
    }

    @IsTest
    static void failsWhenNobodyIsEligibleOrFacilityClosed() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        delete [SELECT Id FROM KYC_Check__c];
        try {
            SyndicationAllocator.allocate(s.facility.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('No eligible'));
        }
        s.facility.Status__c = 'Active';
        update s.facility;
        try {
            SyndicationAllocator.allocate(s.facility.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('closed'));
        }
    }

    @IsTest
    static void closingEnforcesGates() {
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        try {
            ClosingService.close(s.facility.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('must be Allocated'));
        }
        SyndicationAllocator.allocate(s.facility.Id);
        try {
            ClosingService.close(s.facility.Id);
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('precedent'));
        }
    }

    @IsTest
    static void closingSignsCommitmentsAndActivatesDeal() {
        TestDataFactory.Scenario s = TestDataFactory.activeFacility();
        Assert.areEqual('Active', TestDataFactory.reload(s.facility.Id).Status__c);
        Assert.areEqual('Active', [SELECT Stage__c FROM Syndicated_Deal__c WHERE Id = :s.deal.Id].Stage__c);
        Assert.areEqual(3, [SELECT COUNT() FROM Lender_Commitment__c WHERE Facility__c = :s.facility.Id AND Status__c = 'Signed']);
        Assert.areEqual(100000000, [SELECT Total_Commitment__c FROM Syndicated_Deal__c WHERE Id = :s.deal.Id].Total_Commitment__c);
    }
}
