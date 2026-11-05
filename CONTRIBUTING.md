# Contributing

Thanks for helping improve this project.

## Ground rules

1. **Model changes go in `schemas/data-model.json`.** Never hand-edit generated files (`force-app/main/default/{objects,layouts,tabs,applications,permissionsets,customPermissions}`, `schemas/data-dictionary.md`, `schemas/erd.md`, `docs/bpmn/*`). Run the generators instead.
2. **Process changes go in `tools/generate_bpmn.py`** (one definition produces BPMN XML, SVG and the step table).
3. **Every business rule has an ID** in [`docs/05-business-rules.md`](docs/05-business-rules.md) and a test. New behaviour = new or updated rule.
4. **Keep entry points thin.** Controllers, REST resources and triggers authorise and delegate; logic lives in `*Service` classes ([ADR-004](docs/adr/ADR-004-apex-service-layer.md)). New entry points must call `SyndicationSecurity.requireOperator()` / `isOperator()`.
5. **Money maths stays pure** (`LoanMath`, `DayCount`), and every pro-rata split uses `LoanMath.split`.

## Workflow

```bash
python3 tools/generate_metadata.py && python3 tools/generate_bpmn.py
pip install jsonschema
python3 tools/validate_repo.py && python3 tools/validate_schemas.py && python3 tools/verify_math.py
sf project deploy start && sf apex run test --test-level RunLocalTests --wait 15
```

Open a pull request using the template. CI re-runs the offline checks and fails on generator drift.

## Reporting bugs

Include: what you ran, the full error (deploy error or test failure), and your org type (scratch, Developer Edition, sandbox) and API version.
