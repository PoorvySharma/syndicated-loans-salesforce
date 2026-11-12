#!/usr/bin/env python3
"""Generate Salesforce metadata + docs from schemas/data-model.json.

Outputs
  force-app/main/default/{objects,layouts,tabs,permissionsets,applications,customPermissions}
  schemas/data-dictionary.md
  schemas/erd.md

Usage: python3 tools/generate_metadata.py
"""
import json
import shutil
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
MODEL = json.loads((ROOT / "schemas" / "data-model.json").read_text())
SRC = ROOT / "force-app" / "main" / "default"
NS = "http://soap.sforce.com/2006/04/metadata"
HDR = '<?xml version="1.0" encoding="UTF-8"?>\n'
OBJECTS = {o["api"]: o for o in MODEL["objects"]}
CONSOLE_TAB = "Syndication_Console"
APP = "Syndicated_Loans"
PERM_OPERATE = "Syndication_Operate"


def e(v):
    return escape(str(v))


def tag(name, value, indent=4):
    return f"{' ' * indent}<{name}>{e(value)}</{name}>\n"


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def b(v):
    return str(bool(v)).lower()


# ----------------------------------------------------------------- fields
def field_xml(obj, f):
    t = f["type"]
    x = [HDR, f'<CustomField xmlns="{NS}">\n', tag("fullName", f["api"])]
    if f.get("d"):
        x.append(tag("description", f["d"]))
    if f.get("track") and obj.get("history"):
        x.append(tag("trackHistory", "true"))
    x.append(tag("label", f["label"]))

    if t == "Text":
        x += [tag("length", f["length"]), tag("required", b(f.get("required")))]
        if f.get("unique"):
            x += [tag("caseSensitive", "false"), tag("externalId", "true"), tag("unique", "true")]
        x.append(tag("type", "Text"))
    elif t == "LongText":
        x += [tag("length", f["length"]), tag("type", "LongTextArea"), tag("visibleLines", 5)]
    elif t in ("Number", "Currency", "Percent"):
        if f.get("default") is not None:
            x.append(tag("defaultValue", f["default"]))
        x += [tag("precision", f.get("precision", 18)), tag("required", b(f.get("required"))),
              tag("scale", f.get("scale", 2)), tag("type", t)]
    elif t == "Date":
        if f.get("default"):
            x.append(tag("defaultValue", f["default"]))
        x += [tag("required", b(f.get("required"))), tag("type", "Date")]
    elif t == "Checkbox":
        x += [tag("defaultValue", "false"), tag("type", "Checkbox")]
    elif t in ("Picklist", "MultiPicklist"):
        x.append(tag("required", b(f.get("required"))))
        x.append(tag("type", "Picklist" if t == "Picklist" else "MultiselectPicklist"))
        if t == "MultiPicklist":
            x.append(tag("visibleLines", 4))
        x.append("    <valueSet>\n        <restricted>true</restricted>\n        <valueSetDefinition>\n"
                 "            <sorted>false</sorted>\n")
        for v in f["values"]:
            d = b(f.get("default") == v)
            x.append(f"            <value>\n                <fullName>{e(v)}</fullName>\n"
                     f"                <default>{d}</default>\n                <label>{e(v)}</label>\n"
                     f"            </value>\n")
        x.append("        </valueSetDefinition>\n    </valueSet>\n")
    elif t == "Lookup":
        req = f.get("required", False)
        if req:
            x.append(tag("required", "true"))
        x += [tag("deleteConstraint", "Restrict" if req else "SetNull"),
              tag("referenceTo", f["ref"]), tag("relationshipLabel", f["relLabel"]),
              tag("relationshipName", f["rel"]), tag("type", "Lookup")]
    elif t == "MasterDetail":
        x += [tag("referenceTo", f["ref"]), tag("relationshipLabel", f["relLabel"]),
              tag("relationshipName", f["rel"]), tag("relationshipOrder", 0),
              tag("reparentableMasterDetail", "false"), tag("type", "MasterDetail"),
              tag("writeRequiresMasterRead", "false")]
    elif t == "Formula":
        ret = f["returns"]
        if ret in ("Currency", "Number", "Percent"):
            x += [tag("precision", 18), tag("scale", f.get("scale", 2))]
        x += [tag("formula", f["formula"]), tag("formulaTreatBlanksAs", "BlankAsZero"), tag("type", ret)]
    elif t == "Rollup":
        child_obj, child_field = f["field"].split(".")
        target = next(c for c in OBJECTS[child_obj]["fields"] if c["api"] == child_field)
        x += [tag("precision", 18), tag("scale", target.get("scale", 2))]
        for fld, op, val in f.get("filter", []):
            x.append("    <summaryFilterItems>\n" + tag("field", fld, 8) + tag("operation", op, 8)
                     + tag("value", val, 8) + "    </summaryFilterItems>\n")
        x += [tag("summarizedField", f["field"]), tag("summaryForeignKey", f["fk"]),
              tag("summaryOperation", f["op"]), tag("type", "Summary")]
    else:
        raise ValueError(f"Unsupported type {t}")
    x.append("</CustomField>\n")
    return "".join(x)


def object_xml(o):
    x = [HDR, f'<CustomObject xmlns="{NS}">\n']
    if o.get("event"):
        x += [tag("deploymentStatus", "Deployed"), tag("description", o["desc"]),
              tag("eventType", "StandardVolume"), tag("label", o["label"]),
              tag("pluralLabel", o["plural"]), tag("publishBehavior", "PublishAfterCommit")]
    else:
        x += [tag("allowInChatterGroups", "false"), tag("compactLayoutAssignment", "SYSTEM"),
              tag("deploymentStatus", "Deployed"), tag("description", o["desc"]),
              tag("enableActivities", "false"), tag("enableBulkApi", "true"), tag("enableFeeds", "false"),
              tag("enableHistory", b(o.get("history"))), tag("enableReports", "true"),
              tag("enableSearch", "true"), tag("enableSharing", "true"), tag("enableStreamingApi", "true"),
              tag("label", o["label"])]
        n = o["name"]
        x.append("    <nameField>\n")
        if n["type"] == "AutoNumber":
            x += [tag("displayFormat", n["format"], 8), tag("label", n["label"], 8), tag("type", "AutoNumber", 8)]
        else:
            x += [tag("label", n["label"], 8), tag("type", "Text", 8)]
        x.append("    </nameField>\n")
        x += [tag("pluralLabel", o["plural"]), tag("sharingModel", o["sharing"]), tag("visibility", "Public")]
    x.append("</CustomObject>\n")
    return "".join(x)


# ----------------------------------------------------------------- layouts
def children_of(api):
    for o in MODEL["objects"]:
        if o.get("event"):
            continue
        for f in o["fields"]:
            if f["type"] in ("Lookup", "MasterDetail") and f["ref"] == api:
                yield o, f


def layout_xml(o):
    def item(field, behavior):
        return (f"            <layoutItems>\n                <behavior>{behavior}</behavior>\n"
                f"                <field>{field}</field>\n            </layoutItems>\n")

    items = [("Name", "Readonly" if o["name"]["type"] == "AutoNumber" else "Required")]
    for f in o["fields"]:
        if f["type"] in ("Formula", "Rollup"):
            beh = "Readonly"
        elif f["type"] == "MasterDetail" or f.get("required"):
            beh = "Required"
        else:
            beh = "Edit"
        items.append((f["api"], beh))
    half = (len(items) + 1) // 2

    def section(label, cols):
        s = ("    <layoutSections>\n        <customLabel>true</customLabel>\n        <detailHeading>true</detailHeading>\n"
             f"        <editHeading>true</editHeading>\n        <label>{e(label)}</label>\n")
        for col in cols:
            s += "        <layoutColumns>\n" + "".join(item(*i) for i in col) + "        </layoutColumns>\n"
        return s + "        <style>TwoColumnsTopToBottom</style>\n    </layoutSections>\n"

    owned = o["sharing"] != "ControlledByParent"
    sys1 = ([("OwnerId", "Edit")] if owned else []) + [("CreatedById", "Readonly")]
    out = [HDR, f'<Layout xmlns="{NS}">\n', section("Information", [items[:half], items[half:]]),
           section("System Information", [sys1, [("LastModifiedById", "Readonly")]])]
    for child, f in children_of(o["api"]):
        cols = ["NAME"] + (["Status__c"] if any(c["api"] == "Status__c" for c in child["fields"]) else [])
        out.append("    <relatedLists>\n" + "".join(f"        <fields>{c}</fields>\n" for c in cols)
                   + f"        <relatedList>{child['api']}.{f['api']}</relatedList>\n    </relatedLists>\n")
    out += ["    <showEmailCheckbox>false</showEmailCheckbox>\n",
            "    <showHighlightsPanel>false</showHighlightsPanel>\n",
            "    <showInteractionLogPanel>false</showInteractionLogPanel>\n",
            "    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>\n",
            "    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>\n", "</Layout>\n"]
    return "".join(out)


# ----------------------------------------------------------------- permission sets
def apex_classes():
    d = SRC / "classes"
    names = []
    if d.exists():
        for p in sorted(d.glob("*.cls")):
            if not p.stem.endswith("Test") and p.stem != "TestDataFactory":
                names.append(p.stem)
    return names


def tab_names():
    return [CONSOLE_TAB] + [o["api"] for o in MODEL["objects"] if not o.get("standard") and not o.get("event")]


def permset_xml(label, desc, level):
    """level: admin | operator | read"""
    x = [HDR, f'<PermissionSet xmlns="{NS}">\n',
         f"    <applicationVisibilities>\n        <application>{APP}</application>\n        <visible>true</visible>\n    </applicationVisibilities>\n"]
    if level != "read":
        for c in apex_classes():
            x.append(f"    <classAccesses>\n        <apexClass>{c}</apexClass>\n        <enabled>true</enabled>\n    </classAccesses>\n")
        x.append(f"    <customPermissions>\n        <enabled>true</enabled>\n        <name>{PERM_OPERATE}</name>\n    </customPermissions>\n")
    x.append(tag("description", desc))
    for o in MODEL["objects"]:
        if o.get("event"):
            continue  # platform event fields carry no field-level security
        for f in o["fields"]:
            # Required and master-detail fields are always accessible: FLS cannot be set on them.
            if f.get("required") or f["type"] == "MasterDetail":
                continue
            editable = level != "read" and f["type"] not in ("Formula", "Rollup")
            x.append(f"    <fieldPermissions>\n        <editable>{b(editable)}</editable>\n"
                     f"        <field>{o['api']}.{f['api']}</field>\n        <readable>true</readable>\n    </fieldPermissions>\n")
    x += [tag("hasActivationRequired", "false"), tag("label", label)]
    for o in MODEL["objects"]:
        write_ok = level != "read"
        if o["api"] == "Account":
            c, ed, de = write_ok, write_ok, False
        elif o.get("event"):
            c, ed, de = write_ok, False, False
        else:
            c, ed, de = write_ok, write_ok, level == "admin"
        x.append("    <objectPermissions>\n"
                 f"        <allowCreate>{b(c)}</allowCreate>\n        <allowDelete>{b(de)}</allowDelete>\n"
                 f"        <allowEdit>{b(ed)}</allowEdit>\n        <allowRead>true</allowRead>\n"
                 "        <modifyAllRecords>false</modifyAllRecords>\n"
                 f"        <object>{o['api']}</object>\n        <viewAllRecords>false</viewAllRecords>\n    </objectPermissions>\n")
    for t in tab_names():
        x.append(f"    <tabSettings>\n        <tab>{t}</tab>\n        <visibility>Visible</visibility>\n    </tabSettings>\n")
    x.append("</PermissionSet>\n")
    return "".join(x)


# ----------------------------------------------------------------- docs
def type_text(f):
    t = f["type"]
    if t == "MultiPicklist":
        return "Multi-select picklist"
    if t == "Lookup":
        return f"Lookup({f['ref']})"
    if t == "MasterDetail":
        return f"Master-Detail({f['ref']})"
    if t == "Formula":
        return f"Formula ({f['returns']})"
    if t == "Rollup":
        return f"Roll-up ({f['op'].upper()})"
    if t == "Text":
        return f"Text({f['length']})"
    if t == "LongText":
        return f"Long text({f['length']})"
    if t in ("Number", "Currency", "Percent") and "precision" in f:
        return f"{t}({f['precision']},{f['scale']})"
    return t


def details(f):
    t = f["type"]
    bits = []
    if t in ("Picklist", "MultiPicklist"):
        bits.append(", ".join(f["values"]))
    if t == "Formula":
        bits.append("`" + f["formula"] + "`")
    if t == "Rollup":
        flt = "; ".join(f"{a} {o} {c}" for a, o, c in f.get("filter", []))
        bits.append(f["field"] + (f" where {flt}" if flt else ""))
    if t in ("Lookup", "MasterDetail"):
        bits.append(f"relationship `{f['rel']}`")
    if f.get("default") is not None:
        bits.append(f"default: {f['default']}")
    if f.get("unique"):
        bits.append("unique, external id")
    return "<br>".join(bits).replace("|", "\\|")


def anchor(o):
    return (o["label"] + " " + o["api"]).lower().replace("(", "").replace(")", "").replace("`", "").replace("_", "").replace(" ", "-")


def dictionary_md():
    out = ["# Data dictionary\n",
           "> Generated by `tools/generate_metadata.py` from `schemas/data-model.json`. Do not edit by hand.\n",
           "**Req** = required at field level. Master-Detail and Name fields are implicitly required.\n",
           "## Objects\n"]
    for o in MODEL["objects"]:
        out.append(f"- {o['label']} (`{o['api']}`)")
    for o in MODEL["objects"]:
        kind = "Standard object (extended)" if o.get("standard") else ("Platform event" if o.get("event") else "Custom object")
        out.append(f"\n## {o['label']} (`{o['api']}`)\n")
        out.append(f"{o['desc']}\n")
        meta = [f"**Type:** {kind}"]
        if not o.get("standard") and not o.get("event"):
            meta.append(f"**Sharing:** {o['sharing']}")
            meta.append(f"**Name:** {o['name']['type']}" + (f" `{o['name']['format']}`" if o['name']['type'] == 'AutoNumber' else ""))
            meta.append(f"**Field history:** {'on' if o.get('history') else 'off'}")
        out.append(" · ".join(meta) + "\n")
        out.append("| Field | API name | Type | Req | Details | Description |")
        out.append("|---|---|---|:-:|---|---|")
        for f in o["fields"]:
            desc = f.get("d", "").replace("|", "\\|")
            out.append(f"| {f['label']} | `{f['api']}` | {type_text(f)} | {'✓' if f.get('required') else ''} | {details(f)} | {desc} |")
    return "\n".join(out) + "\n"


MERMAID_TYPE = {"Text": "string", "LongText": "string", "Number": "decimal", "Currency": "decimal", "Percent": "decimal",
                "Date": "date", "Checkbox": "boolean", "Picklist": "string", "MultiPicklist": "string",
                "Lookup": "string", "MasterDetail": "string", "Formula": "string", "Rollup": "decimal"}


def erd_md():
    def nm(a):
        return a.replace("__c", "").replace("__e", "")

    rels = []
    for o in MODEL["objects"]:
        for f in o["fields"]:
            if f["type"] in ("Lookup", "MasterDetail"):
                parent, child = nm(f["ref"]), nm(o["api"])
                label = f["api"].replace("__c", "")
                if f["type"] == "MasterDetail":
                    rels.append(f'    {parent} ||--o{{ {child} : "MD {label}"')
                elif f.get("required"):
                    rels.append(f'    {parent} ||--o{{ {child} : "{label}"')
                else:
                    rels.append(f'    {parent} |o--o{{ {child} : "{label}"')
    out = ["# Entity-relationship diagrams\n",
           "> Generated by `tools/generate_metadata.py`. Renders natively on GitHub (Mermaid).\n",
           "Legend: `MD` = Master-Detail (cascade delete, roll-ups, inherited sharing). Other lines are Lookups "
           "(`||` = required, `|o` = optional). Master-Detail depth never exceeds three levels.\n",
           "## 1. Relationships overview\n", "```mermaid", "erDiagram"] + rels + ["```\n",
           "## 2. Full model with fields\n", "```mermaid", "erDiagram"] + rels
    for o in MODEL["objects"]:
        out.append(f"    {nm(o['api'])} {{")
        for f in o["fields"]:
            key = " FK" if f["type"] in ("Lookup", "MasterDetail") else ""
            out.append(f"        {MERMAID_TYPE[f['type']]} {f['api'].replace('__c', '')}{key}")
        out.append("    }")
    out.append("```")
    return "\n".join(out) + "\n"


# ----------------------------------------------------------------- main
def main():
    for d in ("objects", "layouts", "tabs", "permissionsets", "applications", "customPermissions"):
        shutil.rmtree(SRC / d, ignore_errors=True)

    for o in MODEL["objects"]:
        base = SRC / "objects" / o["api"]
        if not o.get("standard"):
            write(base / f"{o['api']}.object-meta.xml", object_xml(o))
        for f in o["fields"]:
            write(base / "fields" / f"{f['api']}.field-meta.xml", field_xml(o, f))
        if not o.get("standard") and not o.get("event"):
            write(SRC / "layouts" / f"{o['api']}-{o['label']} Layout.layout-meta.xml", layout_xml(o))
            write(SRC / "tabs" / f"{o['api']}.tab-meta.xml",
                  HDR + f'<CustomTab xmlns="{NS}">\n    <customObject>true</customObject>\n'
                  '    <motif>Custom20: Bank</motif>\n</CustomTab>\n')

    write(SRC / "tabs" / f"{CONSOLE_TAB}.tab-meta.xml",
          HDR + f'<CustomTab xmlns="{NS}">\n    <flexiPage>{CONSOLE_TAB}</flexiPage>\n'
          '    <label>Syndication Console</label>\n    <motif>Custom20: Bank</motif>\n</CustomTab>\n')

    write(SRC / "applications" / f"{APP}.app-meta.xml",
          HDR + f'<CustomApplication xmlns="{NS}">\n'
          "    <description>End-to-end syndicated loan lifecycle: origination, allocation, closing, drawdowns, interest, consents.</description>\n"
          "    <formFactors>Large</formFactors>\n    <label>Syndicated Loans</label>\n    <navType>Standard</navType>\n"
          + "".join(f"    <tabs>{t}</tabs>\n" for t in tab_names() + ["standard-Account"])
          + "    <uiType>Lightning</uiType>\n</CustomApplication>\n")

    write(SRC / "customPermissions" / f"{PERM_OPERATE}.customPermission-meta.xml",
          HDR + f'<CustomPermission xmlns="{NS}">\n'
          "    <description>Allows running lifecycle actions (allocate, close, drawdown, interest) from the console and REST API.</description>\n"
          "    <label>Syndication Operate</label>\n</CustomPermission>\n")

    for api, label, desc, level in [
        ("Syndication_Admin", "Syndication Admin", "Full access to syndicated loan data and operations, including delete.", "admin"),
        ("Syndication_Operator", "Syndication Operator", "Create/edit loan data and run lifecycle actions. No delete.", "operator"),
        ("Syndication_Read_Only", "Syndication Read Only", "Read-only access for analysts, auditors and reporting users.", "read"),
    ]:
        write(SRC / "permissionsets" / f"{api}.permissionset-meta.xml", permset_xml(label, desc, level))

    write(ROOT / "schemas" / "data-dictionary.md", dictionary_md())
    write(ROOT / "schemas" / "erd.md", erd_md())
    n_obj = len([o for o in MODEL["objects"] if not o.get("standard")])
    n_fld = sum(len(o["fields"]) for o in MODEL["objects"])
    print(f"Generated {n_obj} objects (+Account extension), {n_fld} fields, layouts, tabs, app, 3 permission sets.")


if __name__ == "__main__":
    main()
