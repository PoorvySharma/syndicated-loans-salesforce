#!/usr/bin/env python3
"""Generate BPMN 2.0 XML (with diagram interchange), SVG previews and Mermaid/markdown
descriptions for the syndicated-loan processes from one compact definition.

Outputs (docs/bpmn/):  NN-name.bpmn   NN-name.svg   NN-name.md   and  docs/bpmn/README.md

Open the .bpmn files in https://demo.bpmn.io, Camunda Modeler or any BPMN 2.0 tool.
Usage: python3 tools/generate_bpmn.py
"""
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "bpmn"

SF = "Salesforce"

# Each node: (id, kind, label, lane, implementation note)   kind: start|end|task|auto|gateway
# Each flow: (source, target, label, is_back_edge)
PROCESSES = [
    {
        "slug": "01-origination-and-allocation",
        "title": "Origination, bookbuilding and allocation",
        "summary": "From signed mandate to an active facility: invitations, soft commitments, KYC/sanctions screening, pro-rata allocation, conditions precedent and closing.",
        "lanes": ["Borrower", "Arranger", "Lender", "Agent", SF],
        "nodes": [
            ("s", "start", "Mandate signed", "Arranger", "Deal enters stage Mandate."),
            ("t1", "task", "Create deal and facilities", "Arranger", "`Syndicated_Deal__c`, `Facility__c` (tranche, pricing, maturity)."),
            ("t2", "task", "Invite lenders", "Arranger", "`Lender_Commitment__c` created with Status = Invited."),
            ("t3", "task", "Submit soft commitment", "Lender", "Status = Soft Committed; `Soft_Commit_Amount__c` set."),
            ("t4", "auto", "Screen KYC and sanctions", SF, "`KycGuard.eligible()` - needs current Passed KYC and Sanctions checks."),
            ("t5", "auto", "Allocate with pro-rata cut-back", SF, "`SyndicationAllocator.allocate()` - largest-remainder split, idempotent, publishes `FACILITY_ALLOCATED`."),
            ("g1", "gateway", "Fully allocated?", SF, "Facility status becomes Allocated, otherwise stays Open for Commitments."),
            ("t6", "task", "Widen syndicate or adjust amounts", "Arranger", "Invite more lenders or lenders raise soft commitments, then re-run allocation."),
            ("t7", "task", "Negotiate documents and satisfy CPs", "Borrower", "Facility agreement signed; conditions precedent delivered."),
            ("t8", "task", "Confirm CPs satisfied", "Agent", "`Syndicated_Deal__c.CPs_Satisfied__c` = true."),
            ("t9", "auto", "Close facility", SF, "`ClosingService.close()` - commitments to Signed, facility Active, deal Active, publishes `FACILITY_CLOSED`."),
            ("e", "end", "Facility active", SF, "Ready for drawdowns."),
        ],
        "flows": [
            ("s", "t1", "", False), ("t1", "t2", "", False), ("t2", "t3", "", False), ("t3", "t4", "", False),
            ("t4", "t5", "", False), ("t5", "g1", "", False), ("g1", "t6", "No", False), ("t6", "t2", "re-run", True),
            ("g1", "t7", "Yes", False), ("t7", "t8", "", False), ("t8", "t9", "", False), ("t9", "e", "", False),
        ],
    },
    {
        "slug": "02-drawdown-and-funding",
        "title": "Drawdown and funding",
        "summary": "Borrower utilisation request, agent-side validation, pro-rata notice to every lender, funding confirmation and lender hold updates.",
        "lanes": ["Borrower", "Agent", "Lender", SF],
        "nodes": [
            ("s", "start", "Funding need", "Borrower", "Facility must be Active."),
            ("t1", "task", "Submit drawdown request", "Borrower", "`DrawdownService.request()` or REST `POST /syndication/v1/drawdowns`."),
            ("t2", "auto", "Validate request", SF, "Facility Active, value date not past, within maturity and availability period, amount <= available."),
            ("g1", "gateway", "Valid?", SF, "Business-rule failures reject with a reason instead of raising an error."),
            ("t3", "auto", "Reject with reason", SF, "Status = Rejected; `Rejection_Reason__c`; publishes `DRAWDOWN_REJECTED`."),
            ("e1", "end", "Request rejected", SF, "Borrower is informed."),
            ("t4", "auto", "Split pro-rata and notify lenders", SF, "`LoanMath.split()` over allocated amounts; `Drawdown_Share__c` per lender; reserves availability; publishes `DRAWDOWN_NOTIFIED`."),
            ("t5", "task", "Transfer funds to Agent", "Lender", "Each lender funds its share by the value date."),
            ("t6", "task", "Confirm funding and disburse", "Agent", "`DrawdownService.confirmFunding()`."),
            ("t7", "auto", "Update lender holds and facility drawn", SF, "`Funded_Amount__c` per lender; Drawn roll-up; publishes `DRAWDOWN_FUNDED`."),
            ("e2", "end", "Borrower funded", "Borrower", "Interest accrues from the value date."),
        ],
        "flows": [
            ("s", "t1", "", False), ("t1", "t2", "", False), ("t2", "g1", "", False), ("g1", "t3", "No", False),
            ("t3", "e1", "", False), ("g1", "t4", "Yes", False), ("t4", "t5", "", False), ("t5", "t6", "", False),
            ("t6", "t7", "", False), ("t7", "e2", "", False),
        ],
    },
    {
        "slug": "03-interest-and-distribution",
        "title": "Interest period and payment distribution",
        "summary": "Rate fixing, interest calculation, borrower payment, exact pro-rata distribution to lenders and settlement, repeated each period until maturity or repayment.",
        "lanes": ["Borrower", "Agent", "Lender", SF],
        "nodes": [
            ("s", "start", "Drawdown funded", SF, "Triggered once a drawdown is Funded."),
            ("t1", "auto", "Open interest period", SF, "`InterestService.openNext()` - start = value date or previous end; end capped at maturity."),
            ("t2", "task", "Fix base rate", "Agent", "`InterestService.fixRate()` or REST `POST /syndication/v1/rates`."),
            ("t3", "auto", "Calculate interest", SF, "`InterestService.calculate()` - principal x (max(base,0) + margin) x day-count fraction."),
            ("t4", "task", "Notify borrower of amount due", "Agent", "Interest notice."),
            ("t5", "task", "Pay interest", "Borrower", "Payment on the due date."),
            ("t6", "task", "Record payment", "Agent", "`InterestService.markPaid()`."),
            ("t7", "auto", "Split interest pro-rata", SF, "`InterestService.distribute()` - `Payment_Distribution__c` per lender, sum equals interest to the cent; publishes `INTEREST_DISTRIBUTED`."),
            ("t8", "task", "Settle lender payments", "Agent", "`InterestService.settleDistributions()` with payment-run reference."),
            ("t9", "task", "Receive interest", "Lender", "Lender books the income."),
            ("g1", "gateway", "More periods before maturity?", SF, "Next period opens only when the previous is Distributed."),
            ("e", "end", "Interest cycle complete", SF, "Drawdown repaid or matured."),
        ],
        "flows": [
            ("s", "t1", "", False), ("t1", "t2", "", False), ("t2", "t3", "", False), ("t3", "t4", "", False),
            ("t4", "t5", "", False), ("t5", "t6", "", False), ("t6", "t7", "", False), ("t7", "t8", "", False),
            ("t8", "t9", "", False), ("t9", "g1", "", False), ("g1", "t1", "Yes", True), ("g1", "e", "No", False),
        ],
    },
    {
        "slug": "04-covenant-and-consent",
        "title": "Covenant testing, waivers and lender consent",
        "summary": "Compliance certificate, automatic Pass/Breach derivation, waiver request circulation and commitment-weighted voting.",
        "lanes": ["Borrower", "Agent", "Lender", SF],
        "nodes": [
            ("s", "start", "Test date reached", "Borrower", "Per covenant test frequency."),
            ("t1", "task", "Deliver compliance certificate", "Borrower", "Actual value for the covenant metric."),
            ("t2", "auto", "Record test and derive result", SF, "`CovenantTestTrigger` -> `CovenantService.evaluate()`; Maximum: actual <= threshold, Minimum: actual >= threshold."),
            ("g1", "gateway", "Breach?", SF, "Covenant status rolls to Compliant or Breached; publishes `COVENANT_BREACH`."),
            ("e1", "end", "Covenant compliant", SF, "No action needed."),
            ("t3", "task", "Draft waiver or amendment", "Agent", "`Amendment_Request__c` with required majority (66.67 or 100)."),
            ("t4", "auto", "Circulate to signed lenders", SF, "`ConsentService.circulate()` - one `Lender_Consent__c` per lender, weight snapshot."),
            ("t5", "task", "Respond: consent or decline", "Lender", "`Lender_Consent__c.Response__c`."),
            ("t6", "auto", "Tally weighted votes", SF, "`LenderConsentTrigger` -> `ConsentService.tally()`."),
            ("g2", "gateway", "Outcome?", SF, "Approved when consenting weight >= threshold; Rejected once threshold unreachable; Expired after deadline."),
            ("e2", "end", "Waiver approved", "Agent", "Publishes `AMENDMENT_RESOLVED` (Approved)."),
            ("e3", "end", "Not approved", SF, "Rejected or Expired; publishes `AMENDMENT_RESOLVED`."),
        ],
        "flows": [
            ("s", "t1", "", False), ("t1", "t2", "", False), ("t2", "g1", "", False), ("g1", "e1", "No", False),
            ("g1", "t3", "Yes", False), ("t3", "t4", "", False), ("t4", "t5", "", False), ("t5", "t6", "", False),
            ("t6", "g2", "", False), ("g2", "e2", "Approved", False), ("g2", "e3", "Rejected / expired", False),
            ("g2", "t5", "Still open", True),
        ],
    },
    {
        "slug": "05-secondary-assignment",
        "title": "Secondary-market assignment",
        "summary": "Transfer of part or all of a lender's commitment to a new lender, gated by borrower consent, agent approval and buyer KYC/sanctions.",
        "lanes": ["Seller", "Buyer", "Borrower", "Agent", SF],
        "nodes": [
            ("s", "start", "Seller wants to exit", "Seller", "Trade agreed bilaterally."),
            ("t1", "task", "Create assignment", "Seller", "`Assignment__c` (seller commitment, buyer, amount)."),
            ("t2", "task", "Give consent if required", "Borrower", "Status = Pending Borrower Consent."),
            ("t3", "task", "Approve transfer", "Agent", "Status = Pending Agent Approval."),
            ("t4", "auto", "Check buyer and amount", SF, "`AssignmentService.settle()` - buyer passes KYC/sanctions; amount <= seller allocation."),
            ("g1", "gateway", "Eligible?", SF, "Failure raises a business error and leaves the assignment unsettled."),
            ("t5", "task", "Reject assignment", "Agent", "Status = Rejected."),
            ("e1", "end", "Assignment rejected", "Seller", "No change to holdings."),
            ("t6", "auto", "Move commitment and funded share", SF, "Allocated and funded amounts move seller -> buyer; publishes `ASSIGNMENT_SETTLED`."),
            ("e2", "end", "Assignment settled", "Buyer", "Buyer commitment is Signed."),
        ],
        "flows": [
            ("s", "t1", "", False), ("t1", "t2", "", False), ("t2", "t3", "", False), ("t3", "t4", "", False),
            ("t4", "g1", "", False), ("g1", "t5", "No", False), ("t5", "e1", "", False), ("g1", "t6", "Yes", False),
            ("t6", "e2", "", False),
        ],
    },
]

COL_W, LANE_H, LEFT, TOP, LABEL_W = 180, 170, 60, 20, 40
TASK_W, TASK_H, GW, EV = 120, 64, 50, 36


def layout(p):
    ids = {n[0]: n for n in p["nodes"]}
    fwd = [f for f in p["flows"] if not f[3]]
    col = {n[0]: 0 for n in p["nodes"]}
    for _ in range(len(p["nodes"])):
        for s, t, _l, _b in fwd:
            col[t] = max(col[t], col[s] + 1)
    lane_ix = {l: i for i, l in enumerate(p["lanes"])}
    buckets = {}
    for n in p["nodes"]:
        buckets.setdefault((col[n[0]], n[3]), []).append(n[0])
    pos = {}
    for (c, lane), members in buckets.items():
        k = len(members)
        for j, nid in enumerate(members):
            off = (j - (k - 1) / 2) * 78
            pos[nid] = (LEFT + LABEL_W + 40 + c * COL_W + COL_W / 2,
                        TOP + lane_ix[lane] * LANE_H + LANE_H / 2 + off)
    width = LEFT + LABEL_W + 40 + (max(col.values()) + 1) * COL_W + 30
    return ids, pos, lane_ix, width, TOP + len(p["lanes"]) * LANE_H


def size(kind):
    return {"start": (EV, EV), "end": (EV, EV), "gateway": (GW, GW)}.get(kind, (TASK_W, TASK_H))


def edge_points(p, pos, ids, f):
    s, t, _l, back = f
    sx, sy = pos[s]
    tx, ty = pos[t]
    sw, sh = size(ids[s][1])
    tw, th = size(ids[t][1])
    if back:
        low = max(sy, ty) + max(sh, th) / 2 + 22
        return [(sx, sy + sh / 2), (sx, low), (tx, low), (tx, ty + th / 2)]
    a = (sx + sw / 2, sy)
    b = (tx - tw / 2, ty)
    if abs(sy - ty) < 1:
        return [a, b]
    # Give each branch leaving the same node its own vertical so they never overlap.
    outs = sorted([g for g in p["flows"] if g[0] == s and not g[3] and abs(pos[g[1]][1] - sy) >= 1],
                  key=lambda g: pos[g[1]][1])
    idx = outs.index(f) if f in outs else 0
    mid = min(a[0] + 26 + idx * 22, b[0] - 14)
    return [a, (mid, sy), (mid, ty), b]


def bpmn_xml(p):
    ids, pos, lane_ix, width, height = layout(p)
    key = p["slug"].split("-", 1)[1].replace("-", "_")
    pid = f"Process_{key}"
    x = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" '
         'xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" '
         f'xmlns:di="http://www.omg.org/spec/DD/20100524/DI" id="Defs_{key}" targetNamespace="https://example.org/syndicated-loans">',
         f'  <bpmn:collaboration id="Collab_{key}"><bpmn:participant id="Pool_{key}" name={quoteattr(p["title"])} processRef="{pid}" /></bpmn:collaboration>',
         f'  <bpmn:process id="{pid}" isExecutable="false">',
         '    <bpmn:laneSet id="LaneSet_1">']
    for lane in p["lanes"]:
        x.append(f'      <bpmn:lane id="Lane_{lane_ix[lane]}" name={quoteattr(lane)}>')
        for n in p["nodes"]:
            if n[3] == lane:
                x.append(f'        <bpmn:flowNodeRef>{n[0]}</bpmn:flowNodeRef>')
        x.append("      </bpmn:lane>")
    x.append("    </bpmn:laneSet>")
    for n in p["nodes"]:
        nid, kind, label = n[0], n[1], n[2]
        tag = {"start": "startEvent", "end": "endEvent", "gateway": "exclusiveGateway",
               "task": "userTask", "auto": "serviceTask"}[kind]
        x.append(f'    <bpmn:{tag} id="{nid}" name={quoteattr(label)}>')
        for i, f in enumerate(p["flows"]):
            if f[1] == nid:
                x.append(f"      <bpmn:incoming>Flow_{i}</bpmn:incoming>")
        for i, f in enumerate(p["flows"]):
            if f[0] == nid:
                x.append(f"      <bpmn:outgoing>Flow_{i}</bpmn:outgoing>")
        x.append(f"    </bpmn:{tag}>")
    for i, (s, t, label, _b) in enumerate(p["flows"]):
        nm = f" name={quoteattr(label)}" if label else ""
        x.append(f'    <bpmn:sequenceFlow id="Flow_{i}"{nm} sourceRef="{s}" targetRef="{t}" />')
    x.append("  </bpmn:process>")
    x.append('  <bpmndi:BPMNDiagram id="Diagram_1">')
    x.append(f'    <bpmndi:BPMNPlane id="Plane_1" bpmnElement="Collab_{key}">')
    x.append(f'      <bpmndi:BPMNShape id="Pool_{key}_di" bpmnElement="Pool_{key}" isHorizontal="true"><dc:Bounds x="{LEFT}" y="{TOP}" width="{width - LEFT}" height="{height - TOP}" /></bpmndi:BPMNShape>')
    for lane, i in lane_ix.items():
        x.append(f'      <bpmndi:BPMNShape id="Lane_{i}_di" bpmnElement="Lane_{i}" isHorizontal="true"><dc:Bounds x="{LEFT + LABEL_W - 10}" y="{TOP + i * LANE_H}" width="{width - LEFT - LABEL_W + 10}" height="{LANE_H}" /></bpmndi:BPMNShape>')
    for n in p["nodes"]:
        cx, cy = pos[n[0]]
        w, h = size(n[1])
        extra = ' isMarkerVisible="true"' if n[1] == "gateway" else ""
        x.append(f'      <bpmndi:BPMNShape id="{n[0]}_di" bpmnElement="{n[0]}"{extra}><dc:Bounds x="{cx - w / 2:.0f}" y="{cy - h / 2:.0f}" width="{w}" height="{h}" /></bpmndi:BPMNShape>')
    for i, f in enumerate(p["flows"]):
        x.append(f'      <bpmndi:BPMNEdge id="Flow_{i}_di" bpmnElement="Flow_{i}">')
        for px, py in edge_points(p, pos, ids, f):
            x.append(f'        <di:waypoint x="{px:.0f}" y="{py:.0f}" />')
        x.append("      </bpmndi:BPMNEdge>")
    x += ["    </bpmndi:BPMNPlane>", "  </bpmndi:BPMNDiagram>", "</bpmn:definitions>"]
    return "\n".join(x) + "\n"


def wrap(text, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    return lines + ([cur] if cur else [])


def svg(p):
    ids, pos, lane_ix, width, height = layout(p)
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width + 10} {height + 10}" width="{width + 10}" height="{height + 10}" font-family="Helvetica, Arial, sans-serif" font-size="12">',
         '<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#37474f"/></marker></defs>',
         f'<rect x="0" y="0" width="{width + 10}" height="{height + 10}" fill="#ffffff"/>',
         f'<rect x="{LEFT}" y="{TOP}" width="{width - LEFT}" height="{height - TOP}" fill="none" stroke="#37474f" stroke-width="1.5"/>']
    s.append(f'<text x="{LEFT + 14}" y="{TOP + 16}" font-size="13" font-weight="bold" fill="#263238">{escape(p["title"])}</text>')
    for lane, i in lane_ix.items():
        y = TOP + i * LANE_H
        fill = "#e8f1fb" if lane == SF else ("#f7f7f7" if i % 2 == 0 else "#ffffff")
        s.append(f'<rect x="{LEFT + LABEL_W - 10}" y="{y}" width="{width - LEFT - LABEL_W + 10}" height="{LANE_H}" fill="{fill}" stroke="#90a4ae"/>')
        s.append(f'<rect x="{LEFT}" y="{y}" width="{LABEL_W - 10}" height="{LANE_H}" fill="#cfd8dc" stroke="#90a4ae"/>')
        s.append(f'<text transform="translate({LEFT + 18},{y + LANE_H / 2}) rotate(-90)" text-anchor="middle" font-weight="bold" fill="#263238">{escape(lane)}</text>')
    for i, f in enumerate(p["flows"]):
        pts = edge_points(p, pos, ids, f)
        d = " ".join(f"{px:.0f},{py:.0f}" for px, py in pts)
        dash = ' stroke-dasharray="5,3"' if f[3] else ""
        s.append(f'<polyline points="{d}" fill="none" stroke="#37474f" stroke-width="1.5"{dash} marker-end="url(#ar)"/>')
        if f[2]:
            if f[3]:
                lx, ly = (pts[1][0] + pts[2][0]) / 2, pts[1][1] + 14
            elif len(pts) == 2:
                sibs = [g for g in p["flows"] if g[0] == f[0] and g is not f and not g[3]]
                sibling_up = any(pos[g[1]][1] < pos[f[0]][1] - 1 for g in sibs)
                lx, ly = pts[0][0] + 6, pts[0][1] + (14 if sibling_up else -6)
            else:
                up = pts[2][1] < pts[1][1]
                lx, ly = pts[1][0] + 5, pts[1][1] + (-8 if up else 16)
            s.append(f'<text x="{lx:.0f}" y="{ly:.0f}" font-size="11" fill="#455a64" font-style="italic">{escape(f[2])}</text>')
    for n in p["nodes"]:
        cx, cy = pos[n[0]]
        kind = n[1]
        if kind == "start":
            s.append(f'<circle cx="{cx}" cy="{cy}" r="{EV / 2}" fill="#e8f5e9" stroke="#2e7d32" stroke-width="2"/>')
        elif kind == "end":
            s.append(f'<circle cx="{cx}" cy="{cy}" r="{EV / 2}" fill="#ffebee" stroke="#c62828" stroke-width="4"/>')
        elif kind == "gateway":
            h = GW / 2
            s.append(f'<polygon points="{cx},{cy - h} {cx + h},{cy} {cx},{cy + h} {cx - h},{cy}" fill="#fff8e1" stroke="#f9a825" stroke-width="2"/>')
            s.append(f'<text x="{cx}" y="{cy + 5}" text-anchor="middle" font-size="16" font-weight="bold" fill="#f9a825">X</text>')
        else:
            fill, stroke = ("#e3f2fd", "#1565c0") if kind == "auto" else ("#ffffff", "#37474f")
            s.append(f'<rect x="{cx - TASK_W / 2}" y="{cy - TASK_H / 2}" width="{TASK_W}" height="{TASK_H}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        lines = wrap(n[2], 17 if kind in ("task", "auto") else 22)
        if kind in ("task", "auto"):
            y0 = cy - (len(lines) - 1) * 7
            for j, ln in enumerate(lines):
                s.append(f'<text x="{cx}" y="{y0 + j * 14 + 4}" text-anchor="middle" fill="#212121">{escape(ln)}</text>')
        else:
            base = cy + (EV / 2 if kind != "gateway" else GW / 2) + 14
            for j, ln in enumerate(lines):
                s.append(f'<text x="{cx}" y="{base + j * 13}" text-anchor="middle" font-size="11" fill="#212121">{escape(ln)}</text>')
    s.append("</svg>")
    return "\n".join(s) + "\n"


def mermaid(p):
    out = ["```mermaid", "flowchart LR"]
    for lane in p["lanes"]:
        lid = "L_" + "".join(c for c in lane if c.isalnum())
        out.append(f'  subgraph {lid}["{lane}"]')
        for n in p["nodes"]:
            if n[3] != lane:
                continue
            shape = {"start": '(["{}"])', "end": '(["{}"])', "gateway": '{{"{}"}}',
                     "task": '["{}"]', "auto": '[["{}"]]'}[n[1]].format(n[2])
            out.append(f"    {n[0]}{shape}")
        out.append("  end")
    for s_, t_, label, back in p["flows"]:
        arrow = "-.->" if back else "-->"
        out.append(f"  {s_} {arrow}|{label}| {t_}" if label else f"  {s_} {arrow} {t_}")
    out.append("```")
    return "\n".join(out)


def md(p):
    out = [f"# {p['title']}\n", p["summary"] + "\n",
           f"![{p['title']}]({p['slug']}.svg)\n",
           f"Open the editable model: [`{p['slug']}.bpmn`]({p['slug']}.bpmn) (BPMN 2.0; works in bpmn.io, Camunda Modeler, Signavio import).\n",
           "Legend: white box = manual task, blue box = automated by this project, diamond = exclusive gateway, dashed line = loop back.\n",
           "<details><summary>Text version (Mermaid)</summary>\n", mermaid(p), "\n</details>\n",
           "## Steps and implementation\n", "| # | Step | Actor | Type | Implementation |", "|---|---|---|---|---|"]
    for i, n in enumerate(p["nodes"], 1):
        kind = {"start": "Start event", "end": "End event", "gateway": "Gateway", "task": "Manual task", "auto": "Automated"}[n[1]]
        out.append(f"| {i} | {n[2]} | {n[3]} | {kind} | {n[4]} |")
    return "\n".join(out) + "\n"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        old.unlink()
    index = ["# BPMN process models\n",
             "Generated by `tools/generate_bpmn.py`. Each process ships as BPMN 2.0 XML, an SVG preview and a described step table.\n",
             "| Process | Model | Preview | Description |", "|---|---|---|---|"]
    for p in PROCESSES:
        (OUT / f"{p['slug']}.bpmn").write_text(bpmn_xml(p), encoding="utf-8")
        (OUT / f"{p['slug']}.svg").write_text(svg(p), encoding="utf-8")
        (OUT / f"{p['slug']}.md").write_text(md(p), encoding="utf-8")
        index.append(f"| [{p['title']}]({p['slug']}.md) | [bpmn]({p['slug']}.bpmn) | [svg]({p['slug']}.svg) | {p['summary']} |")
    (OUT / "README.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"Generated {len(PROCESSES)} BPMN processes in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
