# ADR-003: Master-Detail for the Deal → Facility → Commitment/Drawdown hierarchy

- **Status:** Accepted

## Context
Totals (deal commitment, facility drawn/pending/allocated) must always be right, children must not outlive parents, and access should follow the deal.

## Decision
Use Master-Detail for Deal→Facility, Facility→Lender_Commitment/Drawdown/Fee, Deal→Covenant→Covenant_Test and Deal→Amendment_Request→Lender_Consent. Use Lookups for cross-links that must be independently deletable or that would exceed the three-level limit (e.g. `Drawdown_Share__c`, `Interest_Period__c`, `Payment_Distribution__c`, `Assignment__c`, `KYC_Check__c`).

## Consequences
- (+) Declarative roll-up summaries (Total Commitment, Drawn, Pending, Allocated, Soft Commit) with no trigger code and no recalculation bugs.
- (+) Cascade delete and `ControlledByParent` sharing.
- (−) Master-Detail is permanent in practice (not re-parentable) and limited to three levels; some entities are Lookups by necessity.
- (−) Roll-up filters are limited to simple equality, which is why availability uses the *Notified*/*Funded* status split.
