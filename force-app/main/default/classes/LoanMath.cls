/**
 * Pure money helpers. No SOQL/DML, so trivially unit-testable.
 * Assumes 2-decimal currencies (see docs/09-roadmap-and-limitations.md for JPY etc.).
 */
public with sharing class LoanMath {
    public class Slot implements Comparable {
        public Integer idx;
        public Decimal weight;
        public Slot(Integer idx, Decimal weight) {
            this.idx = idx;
            this.weight = weight;
        }
        // Largest weight first; ties broken by original position (stable, deterministic).
        public Integer compareTo(Object other) {
            Slot o = (Slot) other;
            if (weight == o.weight) {
                return idx - o.idx;
            }
            return weight > o.weight ? -1 : 1;
        }
    }

    public static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    /**
     * Splits `total` across `weights` proportionally using the largest-remainder method:
     * every part is rounded DOWN to cents, then leftover cents go to the largest weights first.
     * Guarantees SUM(parts) == total (to the cent).
     */
    public static List<Decimal> split(Decimal total, List<Decimal> weights) {
        List<Decimal> out = new List<Decimal>();
        Decimal sum = 0;
        for (Decimal w : weights) {
            sum += nz(w);
            out.add(0);
        }
        if (total == null || sum <= 0) {
            return out;
        }
        Decimal t = total.setScale(2, RoundingMode.HALF_UP);
        Decimal allocated = 0;
        for (Integer i = 0; i < weights.size(); i++) {
            Decimal part = t*(nz(weights[i])).divide(sum, 10, RoundingMode.DOWN).setScale(2, RoundingMode.DOWN);
            out[i] = part;
            allocated += part;
        }
        Integer cents = ((t - allocated) * 100).intValue();
        List<Slot> slots = new List<Slot>();
        for (Integer i = 0; i < weights.size(); i++) {
            if (nz(weights[i]) > 0) {
                slots.add(new Slot(i, weights[i]));
            }
        }
        slots.sort();
        Integer k = 0;
        while (cents > 0 && !slots.isEmpty()) {
            Integer ix = slots[Math.mod(k, slots.size())].idx;
            out[ix] = out[ix] + 0.01;
            cents--;
            k++;
        }
        return out;
    }
}
