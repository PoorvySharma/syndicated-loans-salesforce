## What and why

## Checklist
- [ ] Model changes made in `schemas/data-model.json` (not in generated files) and `python3 tools/generate_metadata.py` re-run
- [ ] `python3 tools/validate_repo.py`, `validate_schemas.py`, `verify_math.py` pass
- [ ] New or changed business rule has an ID in `docs/05-business-rules.md` and a test
- [ ] Apex tests pass in a scratch org (`sf apex run test`)
