# ADR-005: Platform events as the integration and audit backbone

- **Status:** Accepted

## Context
Downstream systems (risk, accounting, payments, warehouse) need to know about allocations, closings, drawdowns, distributions, breaches and consents without polling or tight coupling.

## Decision
Publish a single `Loan_Event__e` (type, deal id, record id, JSON payload) after every business state change, with *publish after commit* so rolled-back transactions emit nothing. Payload contracts are published as JSON Schema.

## Consequences
- (+) Loose coupling; any subscriber (Apex, Flow, Pub/Sub API, MuleSoft) can consume.
- (+) A single stream is a natural basis for an external immutable audit ledger.
- (−) Delivery is at-least-once and events expire from the bus (retention is limited); consumers must be idempotent and track replay ids.
- (−) One event object with a JSON payload trades type-safety for flexibility; the schemas restore the contract.
