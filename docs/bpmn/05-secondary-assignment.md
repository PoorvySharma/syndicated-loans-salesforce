# Secondary-market assignment

Transfer of part or all of a lender's commitment to a new lender, gated by borrower consent, agent approval and buyer KYC/sanctions.

![Secondary-market assignment](05-secondary-assignment.svg)

Open the editable model: [`05-secondary-assignment.bpmn`](05-secondary-assignment.bpmn) (BPMN 2.0; works in bpmn.io, Camunda Modeler, Signavio import).

Legend: white box = manual task, blue box = automated by this project, diamond = exclusive gateway, dashed line = loop back.

<details><summary>Text version (Mermaid)</summary>

```mermaid
flowchart LR
  subgraph L_Seller["Seller"]
    s(["Seller wants to exit"])
    t1["Create assignment"]
    e1(["Assignment rejected"])
  end
  subgraph L_Buyer["Buyer"]
    e2(["Assignment settled"])
  end
  subgraph L_Borrower["Borrower"]
    t2["Give consent if required"]
  end
  subgraph L_Agent["Agent"]
    t3["Approve transfer"]
    t5["Reject assignment"]
  end
  subgraph L_Salesforce["Salesforce"]
    t4[["Check buyer and amount"]]
    g1{"Eligible?"}
    t6[["Move commitment and funded share"]]
  end
  s --> t1
  t1 --> t2
  t2 --> t3
  t3 --> t4
  t4 --> g1
  g1 -->|No| t5
  t5 --> e1
  g1 -->|Yes| t6
  t6 --> e2
```

</details>

## Steps and implementation

| # | Step | Actor | Type | Implementation |
|---|---|---|---|---|
| 1 | Seller wants to exit | Seller | Start event | Trade agreed bilaterally. |
| 2 | Create assignment | Seller | Manual task | `Assignment__c` (seller commitment, buyer, amount). |
| 3 | Give consent if required | Borrower | Manual task | Status = Pending Borrower Consent. |
| 4 | Approve transfer | Agent | Manual task | Status = Pending Agent Approval. |
| 5 | Check buyer and amount | Salesforce | Automated | `AssignmentService.settle()` - buyer passes KYC/sanctions; amount <= seller allocation. |
| 6 | Eligible? | Salesforce | Gateway | Failure raises a business error and leaves the assignment unsettled. |
| 7 | Reject assignment | Agent | Manual task | Status = Rejected. |
| 8 | Assignment rejected | Seller | End event | No change to holdings. |
| 9 | Move commitment and funded share | Salesforce | Automated | Allocated and funded amounts move seller -> buyer; publishes `ASSIGNMENT_SETTLED`. |
| 10 | Assignment settled | Buyer | End event | Buyer commitment is Signed. |
