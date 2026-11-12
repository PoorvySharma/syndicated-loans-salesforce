# 9. Roadmap and limitations

## Verification status (read this first)

The Apex, metadata and Lightning Web Component in this repository were **authored and statically checked, but not deployed to a live Salesforce org by the author of this package**. What *was* verified offline:

- all XML/JSON well-formed (`tools/validate_repo.py`);
- every custom field/object/relationship referenced in Apex and LWC exists in the data model;
- the numbers asserted in the Apex tests were independently recomputed (`tools/verify_math.py`);
- example payloads validate against the JSON Schemas.

What **you** should do on first use: deploy to a scratch org and run `sf apex run test`. If anything fails to deploy or a test fails, please open an issue with the error text; the generator-based design makes fixes quick (change `schemas/data-model.json` or the generator, regenerate, commit).

## Known limitations (v0.1)

| Area | Limitation | Workaround / plan |
|---|---|---|
| Currency | Amount fields use the org currency. `Currency_Code__c` is informational. 2-decimal rounding is assumed (not JPY). | v0.2: multi-currency with `CurrencyIsoCode` and per-currency scale. |
| Fees | `Fee__c` stores fee terms only; no accrual or invoicing. | v0.2 fee engine (commitment fee on undrawn, agency fee). |
| Repayment | Drawdowns are repaid in full only; no amortisation schedule, partial or mandatory prepayment. | v0.2 repayment schedule object and pro-rata repayment. |
| Interest | Simple interest per period. No compounded RFR (SOFR/SONIA in arrears), no break costs, no default interest. | v0.3 compounded-in-arrears calculator, lookback conventions. |
| Business days | No holiday calendar: dates are taken as given, no business-day adjustment. | v0.2 calendars and following/modified-following adjustment. |
| Funding confirmation | Console "Confirm funding" marks *all* shares funded. No partial/failed lender funding or default handling. | Integrate payment status; `Drawdown_Share__c.Status__c` already supports `Failed`. |
| Assignments | Shares of already-funded drawdowns remain with the seller; only commitment and funded totals move. Borrower consent is a status, not enforced by rule. | v0.2 re-point funded shares and enforce consent rules by facility terms. |
| Consent | One facility-agnostic vote per deal; no per-facility or class voting; defaulting-lender exclusion not modelled. | v0.3 voting classes. |
| Approvals | No maker-checker workflow on actions. | Add Approval Processes/Flow. |
| Scale | Allocation and distribution are synchronous Apex, sized for syndicates of tens to low hundreds of lenders. | Move to Queueable/Batch above governor limits. |
| UI | One console for operators; standard UI for everything else. No lender or borrower portal. | Experience Cloud portal. |
| Reporting | No packaged reports or dashboards. | Add report types and dashboards. |

## Roadmap

- **v0.2** multi-currency, fee accrual, repayment schedules, business-day calendars, report types/dashboards
- **v0.3** compounded RFR interest, break costs, voting classes and defaulting lenders, Experience Cloud portal
- **v0.4** unlocked-package / 2GP packaging, optional namespace, richer Flow/approval templates

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md). Changes to the model go in `schemas/data-model.json`; never hand-edit generated files.
