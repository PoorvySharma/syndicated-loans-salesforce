#!/usr/bin/env bash
# Creates a scratch org, deploys the project, assigns permissions, seeds demo data and opens the console.
# Prerequisites: Salesforce CLI (sf) logged in to a Dev Hub:  sf org login web --set-default-dev-hub
set -euo pipefail
ALIAS="${1:-syndloans}"

sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --set-default --duration-days 14
sf project deploy start --target-org "$ALIAS"
sf org assign permset --name Syndication_Admin --target-org "$ALIAS"
sf apex run --file scripts/apex/seed-demo-data.apex --target-org "$ALIAS"
echo "Running Apex tests..."
sf apex run test --test-level RunLocalTests --wait 15 --result-format human --target-org "$ALIAS"
sf org open --path lightning/n/Syndication_Console --target-org "$ALIAS"
