# ADR-002: Institutions are Accounts with a role multi-select

- **Status:** Accepted

## Context
Borrowers, lenders, arrangers and agents are all legal entities, and one entity often plays several roles across deals (a bank can be arranger, agent and lender).

## Decision
Use the standard `Account` object, extended with `Institution_Roles__c` (multi-select: Borrower, Lender, Arranger, Agent), LEI, country, rating, settlement account and an internal limit. Roles on a *specific* deal are expressed by lookups on the deal (`Borrower__c`, `Arranger__c`, `Agent__c`) and by `Lender_Commitment__c`.

## Consequences
- (+) One record per institution; reuses standard sharing, search, hierarchy and any existing CRM data.
- (+) Avoids duplicate parties and role-specific objects.
- (−) The multi-select is descriptive, not a constraint; deal lookups are what is authoritative.
- (−) Orgs that use Person Accounts or heavy Account customisation should review field/record-type impact.
