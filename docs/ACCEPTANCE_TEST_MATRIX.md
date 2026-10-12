# My Construction Platform: Acceptance Test Matrix

Status: SPECIFICATION ONLY (v0.1, 2026-10-10). This matrix lists tests that must pass before each area is called working. It contains no results except those explicitly marked EXECUTED, which refer to the 0005 test run (84 PASS, 0 FAIL, rolled back) and earlier suites recorded in the project history. Everything else is NOT YET RUN because the feature does not exist yet.

## 1. Conventions

- **Status:** EXECUTED (run against the live database and passed), PARTIAL (some cases executed), NOT BUILT (feature absent, test cannot run), NOT YET RUN (feature exists but this test has not been run).
- **Type:** DB (SQL test in a rolled-back transaction using real roles), UNIT (pure function test with fixed expected values), API (server route or RPC), E2E (browser journey), MANUAL (device or visual check).
- **Roles under test:** anon, customer A, customer B (another customer), supplier A, supplier B, professional, admin, finance admin (once roles are split).
- All DB tests run inside a transaction that is rolled back; row counts must be verified as zero afterwards. No demo data is inserted into the production catalog; any fixture is created and rolled back within the test.
- A test passes only with the stated expected result, including the error code for denials. A statement that succeeds when it should be denied is a failure.
- Each test that is later automated gets a stable ID and is rerun on every change (regression, area 20).

## 2. Matrix

### 1. Product variant and dimension validation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T01-1 | Create variant with required attributes for its category | Accepted | DB | NOT BUILT |
| T01-2 | Variant missing a required attribute | Rejected (23514 or validation error) | DB | NOT BUILT |
| T01-3 | Dimension outside allowed min/max or negative | Rejected | DB | NOT BUILT |
| T01-4 | Two variants with same visual name but different dimension or grade | Stored as separate variants with separate prices | DB | NOT BUILT |
| T01-5 | Tile coverage per box vs dimensions x tiles per box mismatch | Supplier value kept and mismatch flagged | UNIT | NOT BUILT |
| T01-6 | Product `unit` and price `unit` differ | Rejected (23514) | DB | EXECUTED (SS11 to SS13, product-level) |

### 2. Unit conversion
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T02-1 | Exact conversions (length, area, mass) with fixed fixtures, including round trips | Exact expected values within stated rounding | UNIT | NOT BUILT |
| T02-2 | Volume to mass with no material density rule | "Cannot convert", no value | UNIT | NOT BUILT |
| T02-3 | Volume to mass with a recorded material-specific density | Uses that rule and records rule id | UNIT | NOT BUILT |
| T02-4 | Supplier original unit preserved after conversion | Original unit and quantity still stored | DB | NOT BUILT |
| T02-5 | Regional commercial units (per hundred, per thousand) | Defined by data rule | UNIT | NOT BUILT |

### 3. Price calculations
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T03-1 | Total = quantity x unit price using numeric arithmetic | Exact, no float error | UNIT | NOT BUILT |
| T03-2 | Price history on insert, change, status change; none on no-op update | Rows as expected | DB | EXECUTED (H1 to H4) |
| T03-3 | Price trend up, down, none | As expected | DB | EXECUTED (V1 to V3) |
| T03-4 | Negative price, invalid currency or unit | Rejected (23514) | DB | EXECUTED (I1 to I3) |
| T03-5 | Price with effective date in the future / past review date | Not shown as current / shown as outdated | DB | NOT BUILT |

### 4. Bulk-order calculation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T04-1 | Quantity in each tier band, at band edges | Correct tier price at each edge | UNIT/DB | NOT BUILT |
| T04-2 | Overlapping tier bands | Rejected by constraint | DB | NOT BUILT |
| T04-3 | Tier of a hidden or unverified supplier | Not visible to anon | DB | NOT BUILT |
| T04-4 | Supplier tries to mark a tier verified | Denied | DB | NOT BUILT |

### 5. Supplier-specific price visibility
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T05-1 | Unverified, pending, rejected, suspended, unpublished suppliers | Hidden from anon | DB | EXECUTED (B to E, G) |
| T05-2 | Verified, published, non-suspended supplier | Visible | DB | EXECUTED (F) |
| T05-3 | Verified supplier later suspended | Hidden | DB | EXECUTED (H) |
| T05-4 | Supplier sees own non-public price | Visible to owner only | DB | EXECUTED (B2) |
| T05-5 | Out-of-stock or expired price | Per decision D-2 | DB | NOT BUILT (decision pending) |

### 6. Delivery fee calculation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T06-1 | Fee from rules for each component (base, distance band, weight or volume band, loading, unloading, waiting, remote surcharge) | Sum equals expected from fixtures | UNIT | NOT BUILT |
| T06-2 | No applicable rule | Returns "quotation required", never a guessed fee | UNIT | NOT BUILT |
| T06-3 | Destination outside supplier zone | Delivery option not offered | DB | NOT BUILT |
| T06-4 | Fee shown before confirmation equals fee charged | Equal | API | NOT BUILT |
| T06-5 | Expired delivery quote | Blocks confirmation | API | NOT BUILT |

### 7. COD eligibility
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T07-1 | Policy resolution by country, city, supplier, order type, delivery method | Correct allow/deny per fixture | DB | NOT BUILT |
| T07-2 | Order outside COD policy tries COD | Rejected | API | NOT BUILT |
| T07-3 | No policy configured | COD not offered | API | NOT BUILT |

### 8. Cash collection authorisation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T08-1 | Customer tries to mark "Cash collected" or "Payment confirmed" | Denied (42501) | DB | NOT BUILT |
| T08-2 | Supplier records collection; second-party or admin confirmation per policy | State advances only with required actor | DB | NOT BUILT |
| T08-3 | Collection of another supplier's order | Denied | DB | NOT BUILT |
| T08-4 | Customer disputes collected cash | Moves to admin case, supplier cannot force confirmation | DB | NOT BUILT |
| T08-5 | Every cash event writes actor, role and timestamp | Audit rows present | DB | NOT BUILT |

### 9. Order cancellation and refund-state accuracy
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T09-1 | Cancel before confirmation / after dispatch | Allowed or denied per configured policy | DB | NOT BUILT |
| T09-2 | Refund pending > partially refunded > refunded sequence, amounts never exceed paid | Valid transitions only; sum check | DB | NOT BUILT |
| T09-3 | Refund without a prior payment | Rejected | DB | NOT BUILT |
| T09-4 | Order total vs sum of payments vs refunds reconciles | Equal | DB | NOT BUILT |

### 10. Supplier permissions
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T10-1 | Supplier inserts price for another supplier | Denied (42501) | DB | EXECUTED (SS1) |
| T10-2 | Supplier inserts own supplier_submitted price | Allowed | DB | EXECUTED (SS2) |
| T10-3 | Supplier creates or updates verified price (including forged stamps) | Denied (42501) | DB | EXECUTED (SS3, SS3b, SS4, SS4b) |
| T10-4 | Supplier updates another supplier's or market-level price | 0 rows | DB | EXECUTED (SS5, SS6) |
| T10-5 | Forged verified_by / verified_at on a supplier row | Accepted but discarded; row carries no stamp | DB | EXECUTED (SS7 to SS10, SS14) |
| T10-6 | Supplier reads another supplier's orders, quotes, customers | Denied | DB | NOT BUILT |
| T10-7 | Unverified supplier tries to publish | Denied (23514) | DB | EXECUTED (earlier suite, publish rules) |

### 11. Professional verification
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T11-1 | Valid and invalid verification transitions, rejection note required, documents required for review | As specified | DB | EXECUTED (earlier suites; not re-run today) |
| T11-2 | User changes own verification status | Denied | DB | EXECUTED (earlier suites) |
| T11-3 | Verified provider revoked while published | Unpublished atomically, audited | DB | EXECUTED (earlier suites) |
| T11-4 | Suspension unpublishes; unsuspension does not republish | As specified | DB | EXECUTED (earlier suites) |
| T11-5 | Licence or portfolio items need admin approval before public | Hidden until approved | DB | NOT BUILT |

### 12. Unauthorised access and RLS
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T12-1 | Every public table has RLS enabled | None without | DB | EXECUTED (2026-10-10 query) |
| T12-2 | anon cannot execute admin helpers, insert prices, change history | Denied | DB | EXECUTED (2026-10-10 query) |
| T12-3 | Customer cannot write catalog, prices, sources or settings | Denied | DB | EXECUTED (CU1 to CU10) |
| T12-4 | Customer A cannot read customer B's carts, orders, quotes, addresses, evidence | Denied | DB | NOT BUILT |
| T12-5 | Private bucket objects: owner and authorised admin only | Denied otherwise | DB/API | NOT BUILT (0006 not applied) |
| T12-6 | Service-role key not present in client bundle or repository | Absent | MANUAL/CI scan | NOT YET RUN |
| T12-7 | The four client-facing RPCs refuse unauthorised callers | Denied | DB | PARTIAL (earlier suites; targeted re-run pending) |

### 13. Duplicate request and order prevention
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T13-1 | Same idempotency key submitted twice | One record | DB/API | NOT BUILT |
| T13-2 | Double click on confirm | One order | E2E | NOT BUILT |
| T13-3 | Same quote accepted twice | Second attempt rejected | DB | NOT BUILT |

### 14. Stock and price revalidation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T14-1 | Price changed between cart and confirm | Confirmation blocked with change shown | API | NOT BUILT |
| T14-2 | Offer hidden (supplier suspended) between cart and confirm | Blocked | API | NOT BUILT |
| T14-3 | Quantity below MOQ or beyond known stock | Blocked | API | NOT BUILT |

### 15. Delivery status transitions
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T15-1 | Each valid transition by the permitted actor | Allowed | DB | NOT BUILT |
| T15-2 | Skipped or backward transition | Denied | DB | NOT BUILT |
| T15-3 | Customer sets Dispatched; supplier sets Delivery confirmed | Denied | DB | NOT BUILT |
| T15-4 | Delivery address visible only to parties and authorised admin | Denied to others | DB | NOT BUILT |
| T15-5 | Exceptions (delayed, failed attempt, damaged, partial) | Recorded with events | DB | NOT BUILT |

### 16. Review eligibility
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T16-1 | Review without completed job | Rejected | DB | NOT BUILT |
| T16-2 | Second review for the same job | Rejected | DB | NOT BUILT |
| T16-3 | Provider reviews itself / posts for others | Denied | DB | NOT BUILT |
| T16-4 | Review during open dispute | Held per policy (D-15) | DB | NOT BUILT |

### 17. Audit events
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T17-1 | Verification, role, suspension and publish events audited once each | One row each | DB | EXECUTED (earlier suites) |
| T17-2 | Audit log cannot be altered or deleted by ordinary users | Denied | DB | EXECUTED (earlier suites; read access rules to be re-checked) |
| T17-3 | Catalog, price, order, payment, delivery and policy changes audited | Rows present | DB | NOT BUILT (catalog/price edits not yet audited) |

### 18. Concurrent changes
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T18-1 | Two sessions update the same price row at once | No lost update; history has one row per real change; `previous_price` coherent | DB (two connections) | NOT YET RUN: requires two concurrent database sessions, which the current tooling (single transactions via the SQL tool) does not provide; needs a local or scripted harness |
| T18-2 | Publish vs suspend race | Not published after suspension | DB | INSPECTED only: the publish trigger takes a row lock on the owner profile; concurrent behaviour has not been tested |
| T18-3 | Two customers buy the last stock | One succeeds, one told insufficient | DB | NOT BUILT |
| T18-4 | Two admins review the same verification request | One transition wins; second gets invalid-transition error | DB | NOT YET RUN |

### 19. Mobile usability and localisation
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T19-1 | Core journeys on a small phone width and slow connection | Usable, no horizontal scroll | MANUAL/E2E | NOT BUILT |
| T19-2 | Urdu and Arabic show right-to-left layout, correct numerals and dates | Correct | MANUAL | NOT BUILT |
| T19-3 | Every major screen shows loading, empty, error, permission-denied and success states | Present | E2E | NOT BUILT |
| T19-4 | No button implies a transaction that does not exist | Verified by review | MANUAL | NOT BUILT |
| T19-5 | Accessibility: keyboard, labels, contrast | Passes checklist | MANUAL | NOT BUILT |

### 20. Regression
| ID | Case | Expected | Type | Status |
|---|---|---|---|---|
| T20-1 | The 84-case 0005 suite re-run after every migration | 0 FAIL | DB | EXECUTED once (2026-10-09); to be scripted |
| T20-2 | Earlier security suites (189 and 64 cases) re-run after every migration | 0 FAIL | DB | EXECUTED earlier; not re-run today |
| T20-3 | Migration hash comparison remote vs repository | All match | DB | EXECUTED (2026-10-10, 5 of 5 match) |
| T20-4 | Security and Performance advisors reviewed after each migration | No new unreviewed findings | Advisor | EXECUTED (2026-10-10) |
| T20-5 | Row counts zero after each rolled-back run | Zero | DB | EXECUTED (2026-10-10) |

## 3. Release gates
No area is called working until all its rows are EXECUTED with 0 failures, its RLS tests include both allowed and denied cases, and its regression rows remain green. Features whose tests are NOT BUILT are not claimed.

## 4. Known testing limits (today)
- Concurrent-session tests (area 18) need a harness that holds two database connections; the current SQL tool runs one statement batch at a time. This must be solved (local Postgres or scripted clients) before concurrency claims.
- Payment-provider tests need provider sandbox accounts and verified webhooks; none exist.
- UI tests require an application; none exists.
- Results for the 189 and 64 case suites come from earlier sessions and have not been re-run in this task.
