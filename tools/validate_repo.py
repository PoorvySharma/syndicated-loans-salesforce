#!/usr/bin/env python3
"""Offline sanity checks (no org needed): XML well-formed, JSON valid, and every custom
field / object referenced from Apex, LWC and metadata exists in schemas/data-model.json."""
import json, re, sys
import xml.dom.minidom as minidom
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
model = json.loads((ROOT / "schemas/data-model.json").read_text())
objs = {o["api"]: {f["api"] for f in o["fields"]} for o in model["objects"]}
rels = {}  # relationship name -> target object api
for o in model["objects"]:
    for f in o["fields"]:
        if f["type"] in ("Lookup", "MasterDetail"):
            rels[(f["ref"], f["rel"])] = o["api"]   # parent + child-relationship -> child object
            rels[("*", f["api"][:-3] + "__r")] = f["ref"]  # Field__r -> parent object
errors = []

for p in ROOT.rglob("*"):
    if p.suffix == ".xml" or p.name.endswith("-meta.xml"):
        try:
            minidom.parse(str(p))
        except Exception as ex:
            errors.append(f"XML {p.relative_to(ROOT)}: {ex}")
    if p.suffix == ".json" and ".git" not in p.parts:
        try:
            json.loads(p.read_text())
        except Exception as ex:
            errors.append(f"JSON {p.relative_to(ROOT)}: {ex}")

all_fields = set().union(*objs.values()) | {"Name", "Id", "CreatedDate", "OwnerId"}
all_objs = set(objs) | {"Account", "User", "Profile", "PermissionSet", "PermissionSetAssignment"}
src = ""
for p in list((ROOT / "force-app").rglob("*.cls")) + list((ROOT / "force-app").rglob("*.trigger")) + list((ROOT / "force-app").rglob("*.js")):
    src += p.read_text() + "\n"
for tok in sorted(set(re.findall(r"\b([A-Za-z][A-Za-z0-9_]*__[cer])\b", src))):
    if tok.endswith("__c") and tok not in all_fields and tok not in all_objs:
        errors.append(f"Unknown custom field/object referenced in code: {tok}")
    if tok.endswith("__e") and tok not in all_objs:
        errors.append(f"Unknown event: {tok}")
    if tok.endswith("__r"):
        parent_field = tok[:-3] + "__c"          # Lender__r -> Lender__c
        child_rel = {f["rel"] + "__r" for o in model["objects"] for f in o["fields"] if "rel" in f}
        if parent_field not in all_fields and tok not in child_rel:
            errors.append(f"Unknown relationship: {tok}")

if errors:
    print("\n".join(errors)); sys.exit(1)
print(f"OK: {len(objs)} objects, {sum(len(v) for v in objs.values())} fields, all XML/JSON well-formed, all code references resolve.")
