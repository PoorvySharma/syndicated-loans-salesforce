# 8. Deployment and testing

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) v2
- A Dev Hub org (to create scratch orgs) **or** a Developer Edition / sandbox org
- Python 3.9+ (only needed to regenerate metadata or run the offline checks)
- Node 18+ (optional, for LWC tooling)

## Option A: scratch org (recommended)

```bash
git clone https://github.com/<you>/syndicated-loans-salesforce.git
cd syndicated-loans-salesforce

sf org login web --set-default-dev-hub
sf org create scratch --definition-file config/project-scratch-def.json --alias syndloans --set-default --duration-days 14
sf project deploy start
sf org assign permset --name Syndication_Admin
sf apex run --file scripts/apex/seed-demo-data.apex
sf org open --path lightning/n/Syndication_Console
```

Or run `scripts/bootstrap-scratch-org.sh`, which performs these steps.

## Option B: Developer Edition or sandbox

```bash
sf org login web --alias mydev --set-default
sf project deploy start --target-org mydev
sf org assign permset --name Syndication_Admin --target-org mydev
```

## Run the tests

```bash
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
```

What the suite proves (details in [05-business-rules.md](05-business-rules.md)):

| Test class | Scope |
|---|---|
| `LoanMathTest` | Rounding, day-count and interest arithmetic |
| `SyndicationAllocatorTest` | Cut-back, KYC gating, re-run, closing gates |
| `DrawdownInterestTest` | Drawdown validation, pro-rata shares, funding, interest lifecycle |
| `GovernanceTest` | Voting, covenants, assignments |
| `ConsoleAndRestTest` | Console controller, REST API, permission enforcement |
| **`LifecycleEndToEndTest`** | **The whole lifecycle in one transaction with reconciliation checks** |

## Watch the lifecycle run

```bash
sf apex run --file scripts/apex/run-lifecycle.apex
```

The script builds a deal, allocates, closes, draws down, fixes a rate, pays and distributes interest, then prints a reconciliation to the debug log.

## Offline checks (no org needed)

```bash
python3 tools/validate_repo.py     # XML/JSON well-formed; every field referenced in code exists in the model
python3 tools/verify_math.py       # independent Python re-computation of the numbers asserted in the Apex tests
python3 tools/validate_schemas.py  # example payloads validate against the JSON Schemas
python3 tools/check_links.py       # all relative markdown links resolve
python3 tools/generate_metadata.py && python3 tools/generate_bpmn.py && git diff --exit-code   # no generator drift
```

## Continuous integration

`.github/workflows/ci.yml` runs the offline checks on every push and pull request. If you add the repository secret `SFDX_AUTH_URL` (from `sf org display --verbose --target-org <devhub> --json`), the optional job also creates a scratch org, deploys and runs the Apex tests.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Deploy error on a permission set or tab | Re-run `python3 tools/generate_metadata.py`; commit the output. |
| "You need the Syndication Operator or Admin permission set" | `sf org assign permset --name Syndication_Admin` for the running user. |
| Console shows no deals | The user lacks object/field access: assign a permission set. |
| `MIXED_DML_OPERATION` in your own tests | Insert users/permission-set assignments outside `System.runAs`, data inside (see `ConsoleAndRestTest`). |
| Percent displays look wrong | Rates are plain numbers (4.30 = 4.30%) by design. |
