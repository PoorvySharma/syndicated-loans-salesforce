# 7. Integration and events

Two integration surfaces exist: an **outbound event stream** and a small **inbound REST API**. Schemas are in [`schemas/events`](../schemas/events/) and [`schemas/api`](../schemas/api/); examples are in [`schemas/examples`](../schemas/examples/) and are validated in CI.

## 7.1 Outbound: `Loan_Event__e`

A standard-volume platform event published after every business state change.

| Field | Content |
|---|---|
| `Event_Type__c` | One of the types below |
| `Deal_Id__c` | Salesforce Id of the deal |
| `Record_Id__c` | Id of the primary record that changed |
| `Payload__c` | JSON string whose shape depends on the event type |

| Event type | Published by | Payload (key fields) |
|---|---|---|
| `FACILITY_ALLOCATED` | `SyndicationAllocator` | facilityId, commitment, totalSoftCommit, totalAllocated, cutBackPct, blockedLenders[] |
| `FACILITY_CLOSED` | `ClosingService` | facilityId, commitment, lenderCount |
| `DRAWDOWN_NOTIFIED` | `DrawdownService` | drawdownId, amount, valueDate, shares[{commitmentId, amount}] |
| `DRAWDOWN_REJECTED` | `DrawdownService` | drawdownId, reason |
| `DRAWDOWN_FUNDED` | `DrawdownService` | drawdownId, amount |
| `DRAWDOWN_REPAID` | `DrawdownService` | drawdownId, amount |
| `INTEREST_DISTRIBUTED` | `InterestService` | periodId, drawdownId, interestAmount, distributions[{commitmentId, amount}] |
| `AMENDMENT_RESOLVED` | `ConsentService` | amendmentId, outcome, consentPct |
| `COVENANT_BREACH` | `CovenantService` | covenantId, testId, actual, threshold |
| `ASSIGNMENT_SETTLED` | `AssignmentService` | assignmentId, sellerCommitmentId, buyerAccountId, amount |

Machine-readable contract: [`schemas/events/loan-event.schema.json`](../schemas/events/loan-event.schema.json).

### Consuming

- **Inside Salesforce:** an Apex trigger on `Loan_Event__e` (`after insert`), or a Platform-Event-triggered Flow.
- **Outside:** the [Pub/Sub API](https://developer.salesforce.com/docs/platform/pub-sub-api/overview) (gRPC) or CometD subscription to `/event/Loan_Event__e`. Subscribers should be idempotent and track the replay id.

Publishing uses *publish after commit* semantics, so subscribers never see an event for a transaction that rolled back.

## 7.2 Inbound: REST API

Base path: `/services/apexrest/syndication/v1/`. Authenticate with any Salesforce OAuth flow; the calling user needs the **Syndication Operator** (or Admin) permission set. All calls are `POST` with a JSON body and return JSON.

| Resource | Purpose | Request schema | Response schema |
|---|---|---|---|
| `drawdowns` | Create a drawdown request and validate/notify in one call | [`drawdown-request`](../schemas/api/drawdown-request.schema.json) | [`drawdown-response`](../schemas/api/drawdown-response.schema.json) |
| `rates` | Fix a base rate on an interest period, optionally calculating interest | [`rate-fixing-request`](../schemas/api/rate-fixing-request.schema.json) | [`rate-fixing-response`](../schemas/api/rate-fixing-response.schema.json) |

Status codes: `200` success (a business-rule *rejection* of a drawdown is still `200` with `status = Rejected` and a reason), `400` invalid request or violated rule (`{"error": "..."}`), `403` missing permission, `404` unknown resource.

### Example

```bash
sf org display --verbose   # copy the access token and instance URL

curl -sS -X POST "$INSTANCE_URL/services/apexrest/syndication/v1/drawdowns" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"facilityId":"a01XXXXXXXXXXXXXXX","amount":5000000,"valueDate":"2026-12-01"}'
```

```json
{ "id": "a03XXXXXXXXXXXXXXX", "status": "Notified", "rejectionReason": null }
```

## 7.3 Planned integrations (not in v0.1)

| Integration | Direction | Approach |
|---|---|---|
| Reference-rate feed | In | Scheduled Apex or MuleSoft calling `rates` |
| Payment rails / SWIFT / ISO 20022 | Out/In | Subscribe to `DRAWDOWN_NOTIFIED` and `INTEREST_DISTRIBUTED`; post settlement back |
| KYC provider | In | Create/update `KYC_Check__c` from provider callback |
| Document vault | Out | Link agreement and CP documents to the deal |
| Lender portal | In/Out | Experience Cloud over the same objects and consent flow |
