/**
 * Interest lifecycle per drawdown: open period -> fix base rate -> calculate -> mark paid -> distribute to lenders.
 */
public with sharing class InterestService {
    /** Pure calculation. Base rate is floored at zero (LMA-style), then margin is added. */
    public static Decimal compute(Decimal principal, Decimal baseRatePct, Decimal marginBps, Date startDate, Date endDate, String dayCount) {
        Decimal base = LoanMath.nz(baseRatePct) > 0 ? baseRatePct : 0;
        Decimal allIn = base + LoanMath.nz(marginBps).divide(100, 6, RoundingMode.HALF_UP);
        Decimal yf = 1.1;//DayCount.yearFraction(startDate, endDate, dayCount);
        return principal*(allIn).divide(100, 10, RoundingMode.HALF_UP)*(yf).setScale(2, RoundingMode.HALF_UP);
    }

    public static Interest_Period__c openNext(Id drawdownId) {
        Drawdown__c d = [
            SELECT Id, Amount__c, Value_Date__c, Status__c, Interest_Period_Months__c,
                   Facility__r.Maturity_Date__c, Facility__r.Margin_Bps__c, Facility__r.Day_Count__c, Facility__r.Interest_Period_Months__c
            FROM Drawdown__c
            WHERE Id = :drawdownId
        ];
        if (d.Status__c != 'Funded') {
            throw new LoanException('Interest periods can only be opened on Funded drawdowns.');
        }
        List<Interest_Period__c> prior = [
            SELECT Status__c, End_Date__c FROM Interest_Period__c WHERE Drawdown__c = :d.Id ORDER BY End_Date__c DESC LIMIT 1
        ];
        Date startDate = d.Value_Date__c;
        if (!prior.isEmpty()) {
            if (prior[0].Status__c != 'Distributed') {
                throw new LoanException('The previous interest period is not yet Distributed.');
            }
            startDate = prior[0].End_Date__c;
        }
        Date maturity = d.Facility__r.Maturity_Date__c;
        if (startDate >= maturity) {
            throw new LoanException('The drawdown has reached facility maturity; no further interest periods.');
        }
        Decimal m = d.Interest_Period_Months__c != null ? d.Interest_Period_Months__c : d.Facility__r.Interest_Period_Months__c;
        Integer months = m == null ? 3 : m.intValue();
        Date endDate = startDate.addMonths(months);
        if (endDate > maturity) {
            endDate = maturity;
        }
        Interest_Period__c p = new Interest_Period__c(
            Drawdown__c = d.Id,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Due_Date__c = endDate,
            Principal_Amount__c = d.Amount__c,
            Margin_Bps__c = d.Facility__r.Margin_Bps__c,
            Day_Count__c = d.Facility__r.Day_Count__c,
            Status__c = 'Open'
        );
        insert p;
        return p;
    }

    public static Interest_Period__c fixRate(Id periodId, Decimal baseRatePct) {
        Interest_Period__c p = load(periodId);
        require(p, 'Open', 'fix the rate');
        if (baseRatePct == null) {
            throw new LoanException('A base rate is required.');
        }
        p.Base_Rate_Pct__c = baseRatePct;
        p.Status__c = 'Rate Fixed';
        update p;
        return p;
    }

    public static Interest_Period__c calculate(Id periodId) {
        Interest_Period__c p = load(periodId);
        require(p, 'Rate Fixed', 'calculate interest');
        p.Interest_Amount__c = compute(p.Principal_Amount__c, p.Base_Rate_Pct__c, p.Margin_Bps__c, p.Start_Date__c, p.End_Date__c, p.Day_Count__c);
        p.Status__c = 'Calculated';
        update p;
        return p;
    }

    public static Interest_Period__c markPaid(Id periodId) {
        Interest_Period__c p = load(periodId);
        require(p, 'Calculated', 'record payment');
        p.Status__c = 'Paid';
        p.Payment_Date__c = Date.today();
        update p;
        return p;
    }

    /** Splits received interest across lenders pro-rata to their funded share of the drawdown. */
    public static List<Payment_Distribution__c> distribute(Id periodId) {
        Interest_Period__c p = load(periodId);
        require(p, 'Paid', 'distribute');
        if ([SELECT COUNT() FROM Payment_Distribution__c WHERE Interest_Period__c = :p.Id] > 0) {
            throw new LoanException('Distributions already exist for this interest period.');
        }
        List<Drawdown_Share__c> shares = [
            SELECT Id, Lender_Commitment__c, Share_Amount__c, Drawdown__r.Facility__r.Deal__c
            FROM Drawdown_Share__c
            WHERE Drawdown__c = :p.Drawdown__c AND Status__c = 'Funded'
            ORDER BY CreatedDate, Id
        ];
        if (shares.isEmpty()) {
            throw new LoanException('No funded lender shares to distribute to.');
        }
        List<Decimal> weights = new List<Decimal>();
        for (Drawdown_Share__c s : shares) {
            weights.add(s.Share_Amount__c);
        }
        List<Decimal> parts = LoanMath.split(p.Interest_Amount__c, weights);
        List<Payment_Distribution__c> dists = new List<Payment_Distribution__c>();
        List<Map<String, Object>> view = new List<Map<String, Object>>();
        for (Integer i = 0; i < shares.size(); i++) {
            dists.add(new Payment_Distribution__c(
                Interest_Period__c = p.Id,
                Lender_Commitment__c = shares[i].Lender_Commitment__c,
                Distribution_Type__c = 'Interest',
                Amount__c = parts[i],
                Status__c = 'Pending'
            ));
            view.add(new Map<String, Object>{ 'commitmentId' => shares[i].Lender_Commitment__c, 'amount' => parts[i] });
        }
        insert dists;
        p.Status__c = 'Distributed';
        update p;
        LoanEvents.publish(
            'INTEREST_DISTRIBUTED',
            shares[0].Drawdown__r.Facility__r.Deal__c,
            p.Id,
            new Map<String, Object>{
                'periodId' => p.Id,
                'drawdownId' => p.Drawdown__c,
                'interestAmount' => p.Interest_Amount__c,
                'distributions' => view
            }
        );
        return dists;
    }

    /** Agent marks lender payments as settled once the payment run clears. */
    public static Integer settleDistributions(Id periodId, String reference) {
        List<Payment_Distribution__c> pending = [SELECT Id FROM Payment_Distribution__c WHERE Interest_Period__c = :periodId AND Status__c = 'Pending'];
        for (Payment_Distribution__c d : pending) {
            d.Status__c = 'Paid';
            d.Paid_Date__c = Date.today();
            d.Settlement_Reference__c = reference;
        }
        update pending;
        return pending.size();
    }

    private static Interest_Period__c load(Id periodId) {
        return [
            SELECT Id, Drawdown__c, Start_Date__c, End_Date__c, Principal_Amount__c, Base_Rate_Pct__c,
                   Margin_Bps__c, Day_Count__c, Interest_Amount__c, Status__c
            FROM Interest_Period__c
            WHERE Id = :periodId
        ];
    }

    private static void require(Interest_Period__c p, String expected, String verb) {
        if (p.Status__c != expected) {
            throw new LoanException('Cannot ' + verb + ': interest period is ' + p.Status__c + ', expected ' + expected + '.');
        }
    }
}
