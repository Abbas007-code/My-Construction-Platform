# My Construction Platform: Delivery, Payment, Returns and Disputes Specification

Status: SPECIFICATION ONLY (v0.1, 2026-10-10). Nothing here is built. The live database has no delivery, order, payment, dispute or return tables. No payment provider is connected or tested. No delivery fee, vehicle capacity, coverage area or delivery promise is stated in this document; all such values are configuration or supplier quotations.

Related: `PRODUCT_CATALOG_AND_COMMERCE_SPEC.md` (gap legend in Section 1 there), `PROFESSIONAL_SERVICES_SPEC.md`, `ACCEPTANCE_TEST_MATRIX.md`.

## 1. Gap analysis

| Requirement | Tag | Status |
|---|---|---|
| Delivery address, zones, coordinates | MISSING | Only `cities`/`areas` with optional latitude/longitude on cities exist. No address or zone tables. |
| Delivery fee rules | MISSING + DATA | No tables. Rules and rates need supplier or market input. |
| Vehicle types and capacities | MISSING + DATA | Capacities must be supplier-confirmed. |
| Delivery records and status transitions | MISSING | |
| Delivery proof | MISSING | Needs private storage (0006 not applied). |
| Payment records, cash handling | MISSING + DECISION | |
| Payment provider integration | MISSING | Nothing connected. Must not be claimed until tested against the provider's official API and callbacks. |
| Refunds, returns, disputes | MISSING + DECISION | |
| Audit of financial events | PARTIAL | `audit_logs` exists and is written by triggers for verification, roles and suspension; not for money or delivery events. |
| Private evidence upload | MISSING | `0006_storage.sql` written, not applied, not reviewed for evidence use. |

## 2. Delivery model (proposed)

### 2.1 Methods
Supplier pickup; supplier-arranged delivery; platform-coordinated delivery (only where the business actually offers it, DECISION); home delivery; construction-site delivery; scheduled delivery; partial delivery where the supplier allows; bulk and heavy-vehicle delivery; machinery transport; unloading services; crane or specialist unloading where offered. A method is available for an order only if the supplier has enabled it for that zone.

### 2.2 Entities

| Entity | Purpose |
|---|---|
| `delivery_zones` | Named zones defined per supplier or per platform, linked to country, region, city and area. Never assumed from city alone. |
| `vehicle_types` | Admin-managed list (name, description). Capacity fields are optional and carry `source` and `confirmed_by`. No default capacity. |
| `delivery_fee_rules` | Configurable rule rows: base fee, distance band, weight or volume band, loading, unloading, waiting, remote-area surcharge, handling. Each rule has scope (supplier or platform), validity dates and an author. |
| `delivery_quotes` | A quoted fee for one order or one quote request, either computed from rules or entered by the supplier. Has an expiry. |
| `delivery_addresses` | Customer address, contact name and phone, instructions, optional coordinates. Private. |
| `deliveries` | One per shipment (an order can have several shipments for partial delivery). |
| `delivery_events` | Append-only history with actor, timestamp, note, optional proof reference. |

### 2.3 Fee calculation
- Fees come from stored `delivery_fee_rules` or from a supplier `delivery_quote`. If neither can produce a reliable number, the system returns "quotation required" and the customer must wait for a quote before confirming.
- For bulky materials (sand, crush, bricks, cement, steel) a delivery quote is requested or computed before the customer confirms the order if no reliable fee exists.
- The price summary shows delivery, loading, unloading and other charges as separate lines before confirmation. No charge appears after confirmation that was not shown before, unless the customer accepts a documented change.
- Different suppliers in one cart mean separate delivery fees and shipments by default (decision D-4 in the catalog spec).
- Calculation is performed server-side from the stored rules; the browser only displays results.

### 2.4 Status progression
Delivery requested > Delivery scheduled > Loaded > Dispatched > In transit > Arrived > Delivered > Delivery confirmed.

Exceptions: Delayed, Failed attempt, Cancelled, Damaged, Partially delivered, Return requested, Disputed.

Rules:
- Transitions are enforced by a database function; skipping states is not allowed except by listed exception transitions.
- Authorised actors per transition (proposed): supplier or delivery provider moves Scheduled, Loaded, Dispatched, In transit, Arrived, Delivered; the customer confirms receipt (Delivery confirmed) or reports a problem; an administrator may resolve disputes. A customer cannot mark a delivery as Dispatched; a supplier cannot mark Delivery confirmed on the customer's behalf.
- If the customer does not confirm, an auto-confirmation after a waiting period is a policy DECISION (D-9) and must not be assumed.
- Proof of delivery (photo, signature or code) is optional per policy and stored privately.
- Delivery contact details and addresses are visible only to the customer, the assigned supplier or delivery provider for that order, and authorised administrators, and only while the order is active.

## 3. Payments

### 3.1 Policy is configuration
A `payment_policies` configuration resolves, by country, city, supplier, order type and delivery method, which methods are allowed and under what terms. Nothing is hard-coded. Methods:
- Cash on delivery (COD), where approved and operationally supported.
- Cash paid directly to the supplier, where the platform terms permit.
- Bank transfer, when implemented.
- Online payment providers, only after actual integration and verification.

### 3.2 Cash payment definitions (all DECISION until approved)
For each cash policy, the following must be explicitly defined and shown to both parties before the order is confirmed:
1. Who receives the money.
2. When the customer must pay.
3. Whether delivery charges are paid separately.
4. Whether deposits or partial payments are allowed.
5. Who confirms collection.
6. What evidence of payment is required.
7. How the order is reconciled.
8. What happens if cash is refused or the delivery fails.
9. How cancellations, returns and refunds are recorded.

### 3.3 Payment states
Payment pending; Payment processing; Cash due; Cash collected; Payment confirmed; Payment failed; Refund pending; Partially refunded; Refunded.

### 3.4 Authorisation rules
- A customer cannot certify that a supplier received money. "Cash collected" is recorded by the party who received it (supplier or delivery provider), and "Payment confirmed" requires a second party or procedure (for example the customer's acknowledgement plus the supplier's collection record, or an administrator reconciliation), as defined by the approved policy.
- A supplier cannot mark a payment confirmed if the customer disputes it; the case moves to an administrator.
- Online payments change state only from a verified provider event (signature-checked webhook, then a server-side status query). The client never sets a payment to succeeded.
- Nothing simulates a successful payment. Test and demo payments are labelled and use provider sandbox accounts only.
- Raw card data is never stored or logged. Provider tokens and secrets live only in server-side configuration.

### 3.5 Entities (proposed)
`payments` (order, amount, currency, method, state, provider reference), `payment_events` (append-only: actor, role, timestamp, evidence reference, provider event id), `refunds`, `cash_collections` (who, when, amount, evidence), `reconciliations`. Money fields use `numeric` with an explicit currency code. Financial rows are append-only or versioned; corrections are new rows.

### 3.6 Visibility
Financial records are visible to the paying customer, the receiving supplier for their own orders, and finance-authorised administrators only. Support staff see a limited view. No broad "admin sees everything" access to payment data (decision D-6 on role split).

## 4. Returns, damages and disputes

### 4.1 Cases
Damaged goods, incorrect quantity, incorrect item, quality dispute, late or failed delivery, cancellation, refund request. Each case is a `support_cases` record linked to an order or delivery, with state: Opened, Awaiting supplier response, Awaiting customer information, Under review, Resolved (with outcome), Closed.

### 4.2 Rules
- Report windows and return eligibility are policy values per goods type, to be configured before launch (DECISION D-5). The platform does not promise refunds, guaranteed delivery or return acceptance until policy is configured, and the UI must say so where no policy exists.
- Standard merchandise, made-to-order goods, bulk materials and hired machinery each have separate rule sets. Bulk materials (for example a delivered load) usually cannot be returned the same way as boxed goods; this is policy, not code.
- Evidence uploads (photos, documents) go to a private bucket with access limited to the case parties and authorised administrators. Evidence must satisfy size and type limits and is never public.
- Admin resolution records the decision, the reason, who decided and when. Resolutions that move money create refund or adjustment records through the normal financial path.
- Every state change writes an audit event.

## 5. Notifications
Delivery and payment state changes notify the relevant parties. Notification content must not include another party's private address or contact details. Channel and consent rules follow the notification architecture in `ARCHITECTURE.md` (designed, not built).

## 6. Decisions and data needed

| ID | Item |
|---|---|
| D-4 | Combine multi-supplier delivery? |
| D-5 | Cancellation, return, refund policy per goods type |
| D-9 | Auto-confirmation of delivery after a waiting period |
| D-10 | Who may deliver: supplier only, third-party transporters, platform fleet (affects licensing and liability; qualified legal advice recommended) |
| D-11 | Approved cash policies and deposit rules |
| D-12 | Payment methods to support first in Pakistan, and provider selection (current provider terms and availability must be verified before choosing) |
| DATA | Delivery zones, supplier coverage, vehicle capacities, fee levels, loading and unloading charges |

## 7. Implementation notes
- Build order: delivery quotes on quote requests first (supplier-entered), then orders with COD under one approved policy, then rule-based fees, then online payments.
- Every table gets row level security and tests for anon, owner, other customer, supplier party, other supplier, finance admin and non-finance admin before use.
- Idempotency keys on order, payment and refund creation.
- Webhook handlers verify signatures, are idempotent, and log without secrets.
- No migration is created by this task.
