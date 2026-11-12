#!/usr/bin/env python3
"""Independent Python re-implementation of LoanMath / DayCount / InterestService used to
cross-check the numbers asserted in the Apex tests (useful when no org is at hand)."""
from datetime import date
from decimal import Decimal as D, ROUND_DOWN, ROUND_HALF_UP

def split(total, weights):
    w = [D(x or 0) for x in weights]; s = sum(w)
    if total is None or s <= 0: return [D(0)] * len(w)
    t = D(total).quantize(D("0.01"), ROUND_HALF_UP)
    parts = [(t * x / s).quantize(D("0.01"), ROUND_DOWN) for x in w]
    cents = int((t - sum(parts)) * 100)
    order = sorted([i for i, x in enumerate(w) if x > 0], key=lambda i: (-w[i], i))
    k = 0
    while cents > 0 and order:
        parts[order[k % len(order)]] += D("0.01"); cents -= 1; k += 1
    return parts

def yf(a, b, conv):
    if conv == "30E/360":
        d1, d2 = min(a.day, 30), min(b.day, 30)
        return (D(360*(b.year-a.year) + 30*(b.month-a.month) + d2-d1) / 360).quantize(D("1e-10"), ROUND_HALF_UP)
    basis = 365 if conv == "ACT/365" else 360
    return (D((b-a).days) / basis).quantize(D("1e-10"), ROUND_HALF_UP)

def interest(p, base, bps, a, b, conv):
    base = D(base) if D(base) > 0 else D(0)
    all_in = base + (D(bps) / 100)
    return (D(p) * all_in / 100 * yf(a, b, conv)).quantize(D("0.01"), ROUND_HALF_UP)

def check(name, got, want):
    ok = got == want
    print(("PASS " if ok else "FAIL ") + name, got if not ok else "")
    return ok

a, b = date(2026, 1, 15), date(2026, 4, 15)
r = [
    check("split 100/3", split(100, [1, 1, 1]), [D("33.34"), D("33.33"), D("33.33")]),
    check("split sums to 100m", sum(split(100000000, [60e6, 50e6, 40e6])), D(100000000)),
    check("alloc <= soft", all(x <= y for x, y in zip(split(100000000, [60e6, 50e6, 40e6]), [60e6, 50e6, 40e6])), True),
    check("ACT/360 yf", yf(a, b, "ACT/360"), D("0.25")),
    check("ACT/365 yf", yf(a, b, "ACT/365"), D("0.2465753425")),
    check("30E/360 yf", yf(date(2026,1,31), date(2026,3,31), "30E/360"), D("0.1666666667")),
    check("interest ACT/360", interest(30000000, 5.0, 250, a, b, "ACT/360"), D("562500.00")),
    check("interest ACT/365", interest(30000000, 5.0, 250, a, b, "ACT/365"), D("554794.52")),
    check("interest floored", interest(30000000, -0.5, 250, a, b, "ACT/360"), D("187500.00")),
]
parts = split(interest(40000000, 4.30, 250, a, b, "ACT/360"), [24e6 + .006, 20e6, 16e6])
r.append(check("distribution sums to interest", sum(parts), interest(40000000, 4.30, 250, a, b, "ACT/360")))
raise SystemExit(0 if all(r) else 1)
