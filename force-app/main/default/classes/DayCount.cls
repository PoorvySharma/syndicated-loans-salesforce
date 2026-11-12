/**
 * Interest day-count conventions. Returns the accrual year fraction (scale 10).
 */
public with sharing class DayCount {
    public static Decimal yearFraction(Date startDate, Date endDate, String convention) {
        if (startDate == null || endDate == null || endDate < startDate) {
            throw new LoanException('Invalid accrual dates.');
        }
        Decimal days = 0;
        Decimal basis = 360;
        switch on convention {
            when 'ACT/360' {
                days = startDate.daysBetween(endDate);
            }
            when 'ACT/365' {
                days = startDate.daysBetween(endDate);
                basis = 365;
            }
            when '30E/360' {
                Integer d1 = Math.min(startDate.day(), 30);
                Integer d2 = Math.min(endDate.day(), 30);
                days = 360 * (endDate.year() - startDate.year()) + 30 * (endDate.month() - startDate.month()) + (d2 - d1);
            }
            when else {
                throw new LoanException('Unsupported day count convention: ' + convention);
            }
        }
        return days.divide(basis, 10, RoundingMode.HALF_UP);
    }
}
