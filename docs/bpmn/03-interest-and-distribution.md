# Interest period and payment distribution

Rate fixing, interest calculation, borrower payment, exact pro-rata distribution to lenders and settlement, repeated each period until maturity or repayment.

![Interest period and payment distribution](03-interest-and-distribution.svg)

Open the editable model: [`03-interest-and-distribution.bpmn`](03-interest-and-distribution.bpmn) (BPMN 2.0; works in bpmn.io, Camunda Modeler, Signavio import).

Legend: white box = manual task, blue box = automated by this project, diamond = exclusive gateway, dashed line = loop back.

<details><summary>Text version (Mermaid)</summary>

```mermaid
flowchart LR
  subgraph L_Borrower["Borrower"]
    t5["Pay interest"]
  end
  subgraph L_Agent["Agent"]
    t2["Fix base rate"]
    t4["Notify borrower of amount due"]
    t6["Record payment"]
    t8["Settle lender payments"]
  end
  subgraph L_Lender["Lender"]
    t9["Receive interest"]
  end
  subgraph L_Salesforce["Salesforce"]
    s(["Drawdown funded"])
    t1[["Open interest period"]]
    t3[["Calculate interest"]]
    t7[["Split interest pro-rata"]]
    g1{"More periods before maturity?"}
    e(["Interest cycle complete"])
  end
  s --> t1
  t1 --> t2
  t2 --> t3
  t3 --> t4
  t4 --> t5
  t5 --> t6
  t6 --> t7
  t7 --> t8
  t8 --> t9
  t9 --> g1
  g1 -.->|Yes| t1
  g1 -->|No| e
```

</details>

## Steps and implementation

| # | Step | Actor | Type | Implementation |
|---|---|---|---|---|
| 1 | Drawdown funded | Salesforce | Start event | Triggered once a drawdown is Funded. |
| 2 | Open interest period | Salesforce | Automated | `InterestService.openNext()` - start = value date or previous end; end capped at maturity. |
| 3 | Fix base rate | Agent | Manual task | `InterestService.fixRate()` or REST `POST /syndication/v1/rates`. |
| 4 | Calculate interest | Salesforce | Automated | `InterestService.calculate()` - principal x (max(base,0) + margin) x day-count fraction. |
| 5 | Notify borrower of amount due | Agent | Manual task | Interest notice. |
| 6 | Pay interest | Borrower | Manual task | Payment on the due date. |
| 7 | Record payment | Agent | Manual task | `InterestService.markPaid()`. |
| 8 | Split interest pro-rata | Salesforce | Automated | `InterestService.distribute()` - `Payment_Distribution__c` per lender, sum equals interest to the cent; publishes `INTEREST_DISTRIBUTED`. |
| 9 | Settle lender payments | Agent | Manual task | `InterestService.settleDistributions()` with payment-run reference. |
| 10 | Receive interest | Lender | Manual task | Lender books the income. |
| 11 | More periods before maturity? | Salesforce | Gateway | Next period opens only when the previous is Distributed. |
| 12 | Interest cycle complete | Salesforce | End event | Drawdown repaid or matured. |
