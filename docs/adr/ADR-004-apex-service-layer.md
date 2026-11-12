# ADR-004: Business logic in an Apex service layer

- **Status:** Accepted

## Context
Allocation, drawdown and interest calculation need exact decimal arithmetic, ordered validation, idempotency and multi-record transactional behaviour, and must be callable from UI, REST and tests.

## Decision
Implement each lifecycle step in a `*Service` class (`with sharing`), keep money maths in pure classes (`LoanMath`, `DayCount`), and keep controllers, REST resources and triggers thin. Business-rule violations raise `LoanException` with a user-safe message; drawdown validation failures instead *reject with a reason* because they are normal outcomes. Triggers exist only where the behaviour must react to ordinary record edits (consent votes, covenant tests).

## Consequences
- (+) One code path whatever the caller; pure functions are trivial to test; the same logic powers the console, REST API and the end-to-end test.
- (+) Rules are readable and traceable (see [05-business-rules](../05-business-rules.md)).
- (−) Admins cannot change rules declaratively. Configurable thresholds (e.g. required majority) are stored as data where sensible.
- (−) Synchronous Apex bounds syndicate size; see roadmap for Queueable/Batch.

## Alternatives considered
Flow-only (hard to unit-test and to express rounding/pro-rata exactly); trigger-per-object (rules scatter, hard to reuse from REST).
