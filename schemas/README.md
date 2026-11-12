# Schemas

| Path | Description | Generated? |
|---|---|:-:|
| [`data-model.json`](data-model.json) | Complete data model: 16 objects (incl. extended `Account` and the `Loan_Event__e` platform event), 132 fields | source of truth |
| [`data-model.schema.json`](data-model.schema.json) | JSON Schema that validates the structure of `data-model.json` | – |
| [`data-dictionary.md`](data-dictionary.md) | Object/field reference | ✓ |
| [`erd.md`](erd.md) | Entity-relationship diagrams (Mermaid) | ✓ |
| [`state-machines.md`](state-machines.md) | Status transitions per object | – |
| [`events/loan-event.schema.json`](events/loan-event.schema.json) | Contract of the decoded `Loan_Event__e` for all 10 event types | – |
| [`api/`](api/) | Request/response JSON Schemas for the REST API | – |
| [`examples/`](examples/) | Sample payloads, validated against the schemas in CI | – |

Regenerate and validate:

```bash
python3 tools/generate_metadata.py
python3 tools/validate_schemas.py
```
