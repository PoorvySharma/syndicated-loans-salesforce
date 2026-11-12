# 5. Business rules catalogue

Each rule has an ID, a plain-language statement, where it is enforced and the test that proves it. Use the IDs in pull requests and tickets.

| ID | Rule | Enforced in | Proven by |
|---|---|---|---|
| BR-01 | If total eligible soft commitments exceed the facility size, each is cut back pro-rata so allocations sum exactly to the facility size and never exceed any lender's soft commitment. | `SyndicationAllocator`, `LoanMath.split` | `SyndicationAllocatorTest.oversubscribedBookIsCutBackProRata`, `LoanMathTest.splitAlwaysSumsToTotalAndNeverExceedsSoftCommit` |
| BR-02 | A lender may only be allocated with a current (unexpired) **Passed** KYC check **and** a **Passed** Sanctions check. Others are reported as blocked and receive nothing. | `KycGuard`, `SyndicationAllocator` | `lenderWithoutCurrentKycIsBlocked`, `expiredKycBlocksLender`, `failsWhenNobodyIsEligibleOrFacilityClosed` |
| BR-03 | Allocation can be re-run until the facility is Active. Withdrawn/declined lenders lose any allocation. An under-subscribed book allocates in full but stays Open for Commitments. | `SyndicationAllocator` | `rerunAfterWithdrawalReallocates`, `undersubscribedBookAllocatesInFullButStaysOpen` |
| BR-04 | A facility can only close when it is **Allocated**, the Agent has confirmed **CPs satisfied**, and allocated amount equals the commitment. | `ClosingService` | `closingEnforcesGates` |
| BR-05 | Closing converts Allocated commitments to **Signed**. The deal becomes **Active** when every non-cancelled facility is Active. | `ClosingService` | `closingSignsCommitmentsAndActivatesDeal` |
| BR-06 | A drawdown is rejected (with a stored reason, not an error) if: the facility is not Active; the value date is in the past, after maturity or after the availability end; the amount exceeds availability; or there are no signed lenders. | `DrawdownService.validate` | `rejectsWhenAmountExceedsAvailability`, `rejectsPastValueDateAndInactiveFacility` |
| BR-07 | An accepted drawdown is split across signed lenders pro-rata to allocation, summing to the cent (largest-remainder rounding). | `DrawdownService`, `LoanMath.split` | `notifySplitsProRataAndReservesAvailability`, `LoanMathTest` |
| BR-08 | Available = Commitment − Funded drawdowns − Notified (pending) drawdowns. | `Facility__c.Available_Amount__c` | `notifySplitsProRataAndReservesAvailability`, `fundingUpdatesLenderHoldsAndFacilityDrawn` |
| BR-09 | Interest = principal × (max(base rate, 0) + margin) × day-count fraction, rounded half-up to the cent. Conventions: ACT/360, ACT/365, 30E/360. | `InterestService.compute`, `DayCount` | `LoanMathTest.interestComputation`, `dayCountConventions` |
| BR-10 | Interest periods are sequential: the next period opens only after the previous is **Distributed**, starts where the last ended and is capped at maturity. Lifecycle order is Open → Rate Fixed → Calculated → Paid → Distributed. | `InterestService` | `interestLifecycleEndsWithExactDistributions` |
| BR-11 | Received interest is distributed to lenders pro-rata to their funded share of the drawdown; the distributions sum exactly to the interest and cannot be created twice. | `InterestService.distribute` | `interestLifecycleEndsWithExactDistributions`, `LifecycleEndToEndTest` |
| BR-12 | A covenant test is Pass/Breach by direction (Maximum: actual ≤ threshold; Minimum: actual ≥ threshold). Covenant status follows its latest test; a manually recorded Waived is never overwritten; breaches publish an event. | `CovenantService`, `CovenantTestTrigger` | `covenantTestsDeriveResultAndRollStatus` |
| BR-13 | Amendments are voted by commitment weight (snapshot at circulation). Approved at ≥ required majority (default 66.67%, 100% for unanimous). Rejected as soon as the threshold is mathematically unreachable. Expired after the deadline without a decision. | `ConsentService`, `LenderConsentTrigger` | `superMajorityApprovesAndRecordsPercentages`, `amendmentRejectedAsSoonAsThresholdIsUnreachable`, `unanimousMattersNeedEveryLender`, `expiredWhenDeadlinePassesWithoutDecision` |
| BR-14 | An assignment settles only from *Pending Agent Approval*, for a positive amount not exceeding the seller's allocation, to a buyer who passes KYC and sanctions. Allocated and funded amounts move pro-rata; the facility total is unchanged. | `AssignmentService` | `assignmentMovesCommitmentToCompliantBuyer`, `assignmentGuards` |
| BR-15 | Lifecycle actions (console and REST) require the `Syndication_Operate` custom permission, granted by the Admin and Operator permission sets but not Read Only. | `SyndicationSecurity` | `consoleActionsRequireOperatePermission`, `restApiForbiddenWithoutPermission` |
| BR-16 | Every business state change publishes a `Loan_Event__e` with a documented payload. | `LoanEvents` + services | `LifecycleEndToEndTest` (publishing must succeed) |

## Worked example (used by the tests)

A USD 100,000,000 Term Loan A, three lenders offer 60m / 50m / 40m (150m, **1.5x** oversubscribed):

| Lender | Soft | Exact pro-rata | Allocated |
|---|---:|---:|---:|
| Alpha | 60,000,000 | 40,000,000.00 | 40,000,000.01 |
| Beta | 50,000,000 | 33,333,333.33… | 33,333,333.33 |
| Gamma | 40,000,000 | 26,666,666.66… | 26,666,666.66 |
| **Total** | **150,000,000** | | **100,000,000.00** |

Rounding down gives 99,999,999.99; the one remaining cent goes to the largest weight (BR-01).

A 40,000,000 drawdown, SOFR fixed at 4.30%, margin 250 bps, ACT/360 over 90 days: 40,000,000 × 6.80% × 90/360 = 680,000.00 split to the cent across the same three lenders.
