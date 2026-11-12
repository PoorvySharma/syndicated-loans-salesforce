# State machines

Allowed status transitions per object. Solid arrows are enforced by the Apex services; entries marked *(manual)* are set by users or the standard UI and are not guarded in v0.1.

## Syndicated Deal — `Stage__c`

```mermaid
stateDiagram-v2
  [*] --> Mandate
  Mandate --> Structuring: manual
  Structuring --> Syndication: manual
  Syndication --> Documentation: manual
  Documentation --> Closing: manual
  Closing --> Active: ClosingService (all facilities Active)
  Active --> Matured: manual
  Mandate --> Cancelled: manual
  Structuring --> Cancelled: manual
  Syndication --> Cancelled: manual
  Matured --> [*]
  Cancelled --> [*]
```

## Facility — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Structuring
  Structuring --> OpenForCommitments: manual
  OpenForCommitments --> Allocated: allocate (fully allocated)
  Allocated --> OpenForCommitments: re-run allocation (shortfall)
  Allocated --> Active: ClosingService.close (CPs satisfied)
  Active --> Repaid: manual
  Structuring --> Cancelled: manual
  OpenForCommitments --> Cancelled: manual
  Repaid --> [*]
  Cancelled --> [*]
```
*OpenForCommitments* = "Open for Commitments".

## Lender Commitment — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Invited
  Invited --> SoftCommitted: lender offers
  Invited --> Declined: lender declines
  SoftCommitted --> Allocated: allocate (KYC + sanctions pass)
  Allocated --> SoftCommitted: re-run, KYC lapsed
  Allocated --> Signed: close facility
  SoftCommitted --> Withdrawn: manual
  Allocated --> Withdrawn: manual
  Signed --> Withdrawn: assignment of full holding
```

## Drawdown — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Requested
  Requested --> Notified: validate OK, shares created
  Requested --> Rejected: validation failed (reason stored)
  Notified --> Funded: confirm funding
  Funded --> Repaid: repay
  Rejected --> [*]
  Repaid --> [*]
```

## Interest Period — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Open
  Open --> RateFixed: fixRate
  RateFixed --> Calculated: calculate
  Calculated --> Paid: markPaid (borrower paid)
  Paid --> Distributed: distribute (pro-rata)
  Distributed --> [*]
```

## Amendment Request — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Circulated: circulate (weights snapshot)
  Circulated --> Approved: consent at or above required majority
  Circulated --> Rejected: threshold unreachable
  Circulated --> Expired: deadline passed, undecided
  Approved --> [*]
  Rejected --> [*]
  Expired --> [*]
```

## Assignment — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> Proposed
  Proposed --> PendingBorrowerConsent: manual
  PendingBorrowerConsent --> PendingAgentApproval: manual
  Proposed --> PendingAgentApproval: manual (no consent needed)
  PendingAgentApproval --> Settled: AssignmentService.settle
  PendingAgentApproval --> Rejected: manual
  Settled --> [*]
  Rejected --> [*]
```

## Covenant — `Status__c`

```mermaid
stateDiagram-v2
  [*] --> NotTested
  NotTested --> Compliant: latest test Pass
  NotTested --> Breached: latest test Breach
  Compliant --> Breached: latest test Breach
  Breached --> Compliant: latest test Pass
  Compliant --> Waived: latest test Waived
  Breached --> Waived: latest test Waived
```
