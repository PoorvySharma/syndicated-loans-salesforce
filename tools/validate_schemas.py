#!/usr/bin/env python3
"""Validate data-model.json against its schema and every example payload against its JSON Schema.
Requires: pip install jsonschema"""
import json, sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parent.parent
S = ROOT / "schemas"
load = lambda p: json.loads(Path(p).read_text())
fc = FormatChecker()
errors = []

def check(schema_path, doc, label, expect_valid=True):
    v = Draft202012Validator(load(schema_path), format_checker=fc)
    errs = sorted(v.iter_errors(doc), key=lambda e: list(e.path))
    if expect_valid and errs:
        errors.append(f"{label}: {errs[0].message} at {list(errs[0].path)}")
    if not expect_valid and not errs:
        errors.append(f"{label}: expected to be INVALID but passed")

check(S / "data-model.schema.json", load(S / "data-model.json"), "data-model.json")

SCHEMA_FOR = {
    "drawdown-request": S / "api/drawdown-request.schema.json",
    "drawdown-response": S / "api/drawdown-response.schema.json",
    "rate-fixing-request": S / "api/rate-fixing-request.schema.json",
    "rate-fixing-response": S / "api/rate-fixing-response.schema.json",
    "loan-event": S / "events/loan-event.schema.json",
}
n = 0
for ex in sorted((S / "examples").glob("*.json")):
    key = ex.name.split(".")[0]
    check(SCHEMA_FOR[key], load(ex), f"examples/{ex.name}")
    n += 1

# Negative tests: the schemas must actually reject bad payloads.
check(SCHEMA_FOR["drawdown-request"], {"facilityId": "a01Wx000001AbCdIAK", "amount": -5, "valueDate": "2026-12-01"}, "neg: negative amount", False)
check(SCHEMA_FOR["drawdown-request"], {"facilityId": "a01Wx000001AbCdIAK", "amount": 5}, "neg: missing valueDate", False)
check(SCHEMA_FOR["loan-event"], {"eventType": "DRAWDOWN_FUNDED", "recordId": "a03Wx000002XyZaIAK", "payload": {"amount": 1}}, "neg: funded without drawdownId", False)
check(SCHEMA_FOR["loan-event"], {"eventType": "NOT_A_TYPE", "recordId": "a03Wx000002XyZaIAK", "payload": {}}, "neg: unknown event type", False)

if errors:
    print("\n".join(errors)); sys.exit(1)
print(f"OK: data-model.json + {n} example payloads valid; 4 negative cases correctly rejected.")
