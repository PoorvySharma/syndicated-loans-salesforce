# ADR-006: Largest-remainder rounding for all pro-rata splits

- **Status:** Accepted

## Context
Allocating, funding and distributing money pro-rata produces fractions of a cent. Naive rounding makes the parts sum to the total ± a few cents, which is unacceptable for an agent who must pass on every cent received.

## Decision
`LoanMath.split` rounds every part **down** to cents and then hands the leftover cents, one each, to the largest weights first (ties broken by original order). Used for allocation cut-back, drawdown shares and interest distribution.

## Consequences
- (+) Parts always sum exactly to the total; the result is deterministic and no part exceeds its exact share by more than one cent.
- (+) Allocation never exceeds a lender's soft commitment by construction.
- (−) The largest holder systematically receives the odd cent; some facility agreements specify a different rounding rule, in which case `split` is the single place to change.
