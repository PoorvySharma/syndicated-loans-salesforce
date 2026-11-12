# 6. Security and compliance

## Access model

| Layer | Mechanism |
|---|---|
| App visibility | `Syndicated_Loans` Lightning app; tabs granted by permission set |
| Object and field access | Three permission sets generated from the data model |
| Action authorisation | Custom permission `Syndication_Operate` checked in Apex (`SyndicationSecurity`) |
| Record access | Org-wide defaults per object: `ReadWrite` for top-level and transactional objects, `ControlledByParent` for Master-Detail children |
| Query-time enforcement | The console reads with `WITH USER_MODE` (FLS + sharing enforced) |
| Service layer | All classes are `with sharing` |

### Permission sets

| Permission set | Intended user | Create/Edit | Delete | Runs lifecycle actions |
|---|---|:-:|:-:|:-:|
| `Syndication_Admin` | Agent operations lead, administrator | ✓ | ✓ | ✓ |
| `Syndication_Operator` | Agent / arranger operator | ✓ | — | ✓ |
| `Syndication_Read_Only` | Lender analyst, auditor, risk | — | — | — |

Assign with:

```bash
sf org assign permset --name Syndication_Admin
```

### Separation of duties

Lifecycle actions are deliberately separate from data entry. A user can have Create/Edit on records without `Syndication_Operate`; the Apex services run with sharing but are only reachable through entry points that check the permission. The REST endpoint returns **403** without it.

## Compliance gating (KYC and sanctions)

`KycGuard` is the single eligibility check. An institution is eligible only if it has **both**

- a `KYC` check with Status *Passed* and no expiry in the past, and
- a `Sanctions` check with Status *Passed* and no expiry in the past.

It is applied at **allocation** and at **assignment settlement (buyer)**. Expired or missing evidence silently blocks allocation but the lender is *reported* back ("blocked by KYC/sanctions") so the arranger can act.

## Audit trail

1. **Field history** on deals, facilities, commitments, drawdowns, interest periods, covenants, amendments, assignments and KYC checks (status, amount, rate, margin, CP flag).
2. **Loan events.** Every state change publishes `Loan_Event__e` ([07](07-integration-and-events.md)); subscribers can persist an immutable ledger outside Salesforce.
3. **System fields** (created/modified by and date) on every record.

## Out of scope in v0.1 (be aware before production use)

- No encryption at rest beyond platform defaults (consider Shield Platform Encryption for IBANs, LEIs, ratings).
- Field history retention is the platform default (18 months in-app); use Field Audit Trail or the event stream for longer retention.
- No four-eyes/maker-checker approval on actions; add Approval Processes or Flow if your policy requires it.
- No data-residency, retention or GDPR erasure tooling.
- KYC/sanctions records are *evidence holders*; the project does not perform screening itself.
- Regulatory reporting (e.g. credit-risk, transaction reporting) is not included.

This repository is a reference implementation, **not** legal, compliance or financial advice. Have your compliance function review any production adoption.
