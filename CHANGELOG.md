# Changelog

## 0.1.0

- Data model: 16 objects (incl. extended `Account` and `Loan_Event__e`), 132 fields, generated metadata, layouts, tabs, app, permission sets, custom permission.
- Apex services: allocation with KYC gate and pro-rata cut-back, closing, drawdown, interest (3 day-count conventions), consent voting, covenant testing, secondary assignment, REST API, platform events.
- Lightning "Syndication Console" for the whole lifecycle.
- Docs: C4 model (context, container, component, dynamic, deployment), 5 BPMN processes (BPMN 2.0 + SVG), domain primer, business rules, security, integration, deployment, roadmap, 7 ADRs.
- Schemas: data dictionary, ERD, state machines, event and API JSON Schemas with validated examples.
- Tests: 6 Apex test classes (plus a data factory) incl. `LifecycleEndToEndTest`; offline validators; CI.
