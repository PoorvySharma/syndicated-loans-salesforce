# 2. Architecture (C4 model)

The architecture is documented with the [C4 model](https://c4model.com): four zoom levels from system context down to components, plus a dynamic view of one key scenario and a deployment view. All diagrams are Mermaid, so they render directly on GitHub and live next to the code.

| Level | Question it answers | Section |
|---|---|---|
| 1. System context | Who uses the system and what does it talk to? | [2.1](#21-level-1--system-context) |
| 2. Containers | What are the deployable/runtime building blocks? | [2.2](#22-level-2--containers) |
| 3. Components | How is the Salesforce application structured inside? | [2.3](#23-level-3--components) |
| Dynamic | How do the parts collaborate for a drawdown? | [2.4](#24-dynamic-view--drawdown-request) |
| Deployment | Where does it run? | [2.5](#25-deployment-view) |

> Scope note: external systems (payment rails, rate source, KYC provider, document vault) are drawn because the design has explicit integration points for them. In v0.1 they are **not implemented**; the project proves the core lifecycle inside Salesforce. See [09-roadmap-and-limitations.md](09-roadmap-and-limitations.md).

## 2.1 Level 1 — System context

```mermaid
C4Context
  title System context: Syndicated Loans on Salesforce

  Person(arranger, "Arranger / Bookrunner", "Structures the deal, runs bookbuilding, invites lenders")
  Person(agent, "Facility Agent", "Administers the loan: CPs, drawdowns, rate fixing, payments, consents")
  Person(lender, "Lender", "Commits to a share of a facility, funds drawdowns, receives interest")
  Person(borrower, "Borrower Treasury", "Requests drawdowns, pays interest, delivers compliance certificates")
  Person(compliance, "Compliance Officer", "Maintains KYC / sanctions evidence")

  System(sl, "Syndicated Loans", "Salesforce application: deal and facility structuring, allocation, closing, drawdowns, interest, covenants, consents, assignments")

  System_Ext(rates, "Reference rate source", "SOFR / EURIBOR / SONIA fixings (manual or API in v0.1)")
  System_Ext(payments, "Payment / settlement rails", "Cash movement between lenders, agent and borrower")
  System_Ext(kyc, "KYC / sanctions provider", "Screening results")
  System_Ext(erp, "Downstream systems", "Risk, accounting, data warehouse consuming loan events")

  Rel(arranger, sl, "Creates deals, runs allocation", "Lightning UI")
  Rel(agent, sl, "Runs lifecycle actions", "Syndication Console")
  Rel(lender, sl, "Soft commits, consents", "UI / future portal")
  Rel(borrower, sl, "Drawdown requests", "REST API / agent proxy")
  Rel(compliance, sl, "Records KYC checks", "Lightning UI")
  Rel(rates, sl, "Rate fixings", "REST API")
  Rel(kyc, sl, "Check results", "Future integration")
  Rel(sl, payments, "Payment instructions", "Future integration")
  Rel(sl, erp, "Loan Events", "Platform Events / Pub-Sub API")
```

## 2.2 Level 2 — Containers

In Salesforce terms a "container" is a separately deployable or independently running unit of the platform.

```mermaid
C4Container
  title Containers: Syndicated Loans

  Person(agent, "Agent / Arranger operator", "Uses the console and standard record pages")
  System_Ext(ext, "External callers", "Rate source, borrower portal, integrations")
  System_Ext(sub, "Event subscribers", "Risk, accounting, warehouse")

  System_Boundary(sl, "Salesforce org") {
    Container(lwc, "Syndication Console", "Lightning Web Component", "Deal board: facilities, lenders, drawdowns, interest periods and one-click lifecycle actions")
    Container(ui, "Standard UI", "Lightning record pages, layouts, tabs", "CRUD on all 14 custom objects, related lists, field history")
    Container(rest, "Integration API", "Apex REST /syndication/v1", "POST drawdowns and rate fixings; permission-gated")
    Container(app, "Domain services", "Apex (with sharing)", "Allocation, closing, drawdown, interest, consent, covenant, assignment, KYC guard")
    ContainerDb(data, "Loan data model", "Custom objects, roll-ups, formulas", "Deal, facility, commitments, drawdowns, interest, covenants, amendments, KYC")
    Container(bus, "Loan Event bus", "Platform Event Loan_Event__e", "Every business state change is published")
    Container(sec, "Access control", "Permission sets + custom permission", "Syndication Admin / Operator / Read Only, Syndication_Operate")
  }

  Rel(agent, lwc, "Uses", "HTTPS")
  Rel(agent, ui, "Uses", "HTTPS")
  Rel(lwc, app, "Calls", "@AuraEnabled")
  Rel(ext, rest, "POST JSON", "HTTPS + OAuth")
  Rel(rest, app, "Invokes")
  Rel(ui, data, "Reads/writes")
  Rel(app, data, "SOQL / DML", "with sharing")
  Rel(app, bus, "Publishes events", "EventBus.publish")
  Rel(bus, sub, "Streams", "Pub/Sub API / CometD")
  Rel(sec, app, "Authorises")
```

Key decisions behind this shape are recorded as ADRs: [ADR-001](adr/ADR-001-single-source-data-model.md) (generated metadata), [ADR-004](adr/ADR-004-apex-service-layer.md) (service layer), [ADR-005](adr/ADR-005-platform-events.md) (events).

## 2.3 Level 3 — Components

The internals of the *Domain services* container and its entry points.

```mermaid
C4Component
  title Components: Apex domain services

  Container_Boundary(entry, "Entry points") {
    Component(ctrl, "SyndicationConsoleController", "Apex @AuraEnabled", "Reads in USER_MODE; single perform() dispatcher for lifecycle actions")
    Component(restc, "SyndicationRestApi", "Apex @RestResource", "POST /drawdowns and /rates")
    Component(trg1, "LenderConsentTrigger", "Apex trigger", "Stamps response date, re-tallies the vote")
    Component(trg2, "CovenantTestTrigger", "Apex trigger", "Derives Pass/Breach, rolls covenant status")
  }

  Container_Boundary(domain, "Domain services") {
    Component(alloc, "SyndicationAllocator", "Apex", "Pro-rata cut-back with KYC screening; idempotent")
    Component(close, "ClosingService", "Apex", "Gates: Allocated, CPs satisfied, amounts reconcile; signs commitments")
    Component(draw, "DrawdownService", "Apex", "Request, validate, pro-rata notice, fund, repay")
    Component(int, "InterestService", "Apex", "Open period, fix rate, calculate, pay, distribute, settle")
    Component(cons, "ConsentService", "Apex", "Circulate, weighted tally, approve / reject / expire")
    Component(cov, "CovenantService", "Apex", "Evaluate tests, roll status, raise breach events")
    Component(assign, "AssignmentService", "Apex", "Settle secondary transfers")
  }

  Container_Boundary(shared, "Shared kernel") {
    Component(math, "LoanMath", "Apex (pure)", "Largest-remainder split: parts always sum to the total to the cent")
    Component(dc, "DayCount", "Apex (pure)", "ACT/360, ACT/365, 30E/360")
    Component(kycg, "KycGuard", "Apex", "Eligibility = current KYC + Sanctions passes")
    Component(secc, "SyndicationSecurity", "Apex", "Syndication_Operate custom permission check")
    Component(ev, "LoanEvents", "Apex", "Publishes Loan_Event__e")
    Component(ex, "LoanException", "Apex", "User-safe business rule violation")
  }

  Rel(ctrl, secc, "requireOperator()")
  Rel(ctrl, alloc, "ALLOCATE")
  Rel(ctrl, close, "CLOSE_FACILITY")
  Rel(ctrl, draw, "REQUEST / NOTIFY / FUND / REPAY")
  Rel(ctrl, int, "OPEN / FIX / CALC / PAID / DISTRIBUTE")
  Rel(restc, secc, "isOperator()")
  Rel(restc, draw, "drawdowns")
  Rel(restc, int, "rates")
  Rel(trg1, cons, "tally()")
  Rel(trg2, cov, "evaluate(), rollStatus()")
  Rel(alloc, kycg, "eligible()")
  Rel(alloc, math, "split()")
  Rel(draw, math, "split()")
  Rel(int, math, "split()")
  Rel(int, dc, "yearFraction()")
  Rel(assign, kycg, "eligible()")
  Rel(alloc, ev, "publish")
  Rel(close, ev, "publish")
  Rel(draw, ev, "publish")
  Rel(int, ev, "publish")
  Rel(cons, ev, "publish")
  Rel(cov, ev, "publish")
  Rel(assign, ev, "publish")
```

Design rules visible in the diagram:

- **Entry points contain no business logic.** The console, REST API and triggers only authorise, parse and delegate.
- **Money maths is pure and isolated** (`LoanMath`, `DayCount`): no SOQL or DML, so it is unit-testable without data.
- **Services never call each other sideways**, except through the shared kernel. Orchestration across services happens in the entry point or the caller.
- **Every service publishes a `Loan_Event__e`** after its state change, giving integration and audit a single stream.

## 2.4 Dynamic view — drawdown request

```mermaid
C4Dynamic
  title Dynamic view: drawdown request through to funding

  Person(agent, "Agent", "Facility agent operator")
  Container(lwc, "Syndication Console", "LWC", "UI")
  Container(app, "Domain services", "Apex", "DrawdownService + LoanMath")
  ContainerDb(data, "Loan data model", "Custom objects", "Drawdown, Drawdown_Share, Lender_Commitment")
  Container(bus, "Loan Event bus", "Platform Event", "Loan_Event__e")
  System_Ext(sub, "Event subscribers", "Risk, accounting")

  Rel(agent, lwc, "1. Requests drawdown")
  Rel(lwc, app, "2. perform(REQUEST_DRAWDOWN, NOTIFY_DRAWDOWN)")
  Rel(app, data, "3. Validates availability, inserts Drawdown, computes pro-rata Drawdown_Shares")
  Rel(app, bus, "4. Publishes DRAWDOWN_NOTIFIED")
  Rel(agent, lwc, "5. Confirms funding")
  Rel(lwc, app, "6. perform(FUND_DRAWDOWN)")
  Rel(app, data, "7. Marks shares funded, updates lender holds")
  Rel(app, bus, "8. Publishes DRAWDOWN_FUNDED")
  Rel(bus, sub, "9. Streams events")
```

## 2.5 Deployment view

```mermaid
C4Deployment
  title Deployment: from GitHub to a Salesforce org

  Deployment_Node(dev, "Developer / CI runner", "Linux, macOS or Windows") {
    Container(cli, "Salesforce CLI + Python 3", "sf, python3", "Deploys source; regenerates metadata from the data model")
    Container(repo, "Git repository", "GitHub", "force-app, schemas, docs, tools")
  }

  Deployment_Node(org, "Salesforce org", "Scratch org / Developer Edition / Sandbox") {
    Deployment_Node(platform, "Lightning Platform", "Multitenant") {
      Container(meta, "Deployed metadata", "Objects, fields, layouts, tabs, app, permission sets", "Generated from schemas/data-model.json")
      Container(code, "Apex and LWC", "Classes, triggers, Lightning Web Component", "Domain services, REST API, console")
    }
  }

  Rel(repo, cli, "Checkout")
  Rel(cli, meta, "sf project deploy start", "Metadata API")
  Rel(cli, code, "sf project deploy start", "Metadata API")
```

## Rendering tips

- GitHub renders these natively. If a viewer shows raw text, paste the block into <https://mermaid.live>.
- Mermaid's C4 support is still marked experimental upstream; layout can vary slightly between versions. The *content* (elements and relationships) is the source of truth.
