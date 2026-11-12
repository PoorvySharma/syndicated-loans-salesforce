# ADR-007: A custom permission gates lifecycle actions

- **Status:** Accepted

## Context
Editing data and *performing* lifecycle actions (allocate, close, fund, distribute) have different risk. Object-level Edit permission on `Drawdown__c` should not by itself let a user fund it.

## Decision
Define the custom permission `Syndication_Operate`, granted by the Admin and Operator permission sets, and check it with `FeatureManagement.checkPermission` in the console controller and REST API. Read-only users never get it.

## Consequences
- (+) Clear separation of duties, easy to audit ("who has Syndication Operate?"), usable in Flow/validation too.
- (−) Services themselves do not re-check (they are internal); any new entry point must call `SyndicationSecurity.requireOperator()`.
