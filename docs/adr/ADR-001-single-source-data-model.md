# ADR-001: One data model file generates the Salesforce metadata and the docs

- **Status:** Accepted
- **Date:** 2026-11-05

## Context
A 16-object, 130+ field model expressed as hand-written Salesforce XML is verbose, error-prone and drifts from its documentation (data dictionary, ERD).

## Decision
`schemas/data-model.json` is the single source of truth. `tools/generate_metadata.py` produces objects, fields, layouts, tabs, the app, permission sets and custom permission, plus `schemas/data-dictionary.md` and `schemas/erd.md`. CI fails if committed output differs from regenerated output.

## Consequences
- (+) Docs, ERD and org metadata cannot disagree; reviewing a model change is a small JSON diff.
- (+) Consistent conventions (history tracking, FLS, layouts) are applied mechanically.
- (−) Contributors must run the generator; hand-edits to generated files are lost.
- (−) The generator supports only the field types used here; new types need generator support.

## Alternatives considered
Hand-written XML (drift, noise); Salesforce `sf` schema export (the wrong direction: org-to-source, no docs).
