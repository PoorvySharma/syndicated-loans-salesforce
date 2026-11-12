@IsTest
private class LoanMathTest {
    @IsTest
    static void splitDistributesRemainderCentsToLargestWeight() {
        List<Decimal> parts = LoanMath.split(100, new List<Decimal>{ 1, 1, 1 });
        Assert.areEqual(33.34, parts[0]);
        Assert.areEqual(33.33, parts[1]);
        Assert.areEqual(33.33, parts[2]);
    }

    @IsTest
    static void splitAlwaysSumsToTotalAndNeverExceedsSoftCommit() {
        List<Decimal> soft = new List<Decimal>{ 60000000, 50000000, 40000000 };
        List<Decimal> parts = LoanMath.split(100000000, soft);
        Assert.areEqual(100000000, TestDataFactory.sum(parts));
        for (Integer i = 0; i < parts.size(); i++) {
            Assert.isTrue(parts[i] <= soft[i], 'allocation must not exceed soft commitment');
        }
    }

    @IsTest
    static void splitHandlesZeroNullAndEmpty() {
        Assert.areEqual(0, TestDataFactory.sum(LoanMath.split(100, new List<Decimal>{ 0, 0 })));
        Assert.areEqual(0, TestDataFactory.sum(LoanMath.split(null, new List<Decimal>{ 1, 2 })));
        Assert.areEqual(0, LoanMath.split(100, new List<Decimal>()).size());
        List<Decimal> withNull = LoanMath.split(10, new List<Decimal>{ null, 5 });
        Assert.areEqual(0, withNull[0]);
        Assert.areEqual(10, withNull[1]);
    }

    @IsTest
    static void nzTreatsNullAsZero() {
        Assert.areEqual(0, LoanMath.nz(null));
        Assert.areEqual(5, LoanMath.nz(5));
    }

    @IsTest
    static void dayCountConventions() {
        Date a = Date.newInstance(2026, 1, 15);
        Date b = Date.newInstance(2026, 4, 15);
        Assert.areEqual(0.25, DayCount.yearFraction(a, b, 'ACT/360'));
        Assert.areEqual(0.2465753425, DayCount.yearFraction(a, b, 'ACT/365'));
        Assert.areEqual(0.1666666667, DayCount.yearFraction(Date.newInstance(2026, 1, 31), Date.newInstance(2026, 3, 31), '30E/360'));
    }

    @IsTest
    static void dayCountRejectsBadInput() {
        Date a = Date.newInstance(2026, 1, 15);
        try {
            DayCount.yearFraction(a, a.addDays(-1), 'ACT/360');
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Invalid'));
        }
        try {
            DayCount.yearFraction(a, a.addDays(1), 'BOGUS');
            Assert.fail('expected exception');
        } catch (LoanException e) {
            Assert.isTrue(e.getMessage().contains('Unsupported'));
        }
    }

    @IsTest
    static void interestComputation() {
        Date a = Date.newInstance(2026, 1, 15);
        Date b = Date.newInstance(2026, 4, 15);
        // 30m x (5.00% + 2.50%) x 90/360
        Assert.areEqual(562500.00, InterestService.compute(30000000, 5.0, 250, a, b, 'ACT/360'));
        Assert.areEqual(554794.52, InterestService.compute(30000000, 5.0, 250, a, b, 'ACT/365'));
        // Negative benchmark is floored at zero: 30m x 2.50% x 90/360
        Assert.areEqual(187500.00, InterestService.compute(30000000, -0.5, 250, a, b, 'ACT/360'));
    }
}
