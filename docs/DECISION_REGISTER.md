# My Construction Platform: Decision Register

Status: v0.1, 2026-10-10. Compiled from `PRODUCT_CATALOG_AND_COMMERCE_SPEC.md`, `DELIVERY_AND_PAYMENT_SPEC.md`, `PROFESSIONAL_SERVICES_SPEC.md` and `ACCEPTANCE_TEST_MATRIX.md`, plus questions raised by the source-control task.

**Nothing in this register has been decided.** Each "recommended default" is a proposal only. No decision here has been implemented, no table has been created, and none of these items changes the database until you approve it and a migration is reviewed.

How to read: "Approval needed" = YES means I will not implement anything that depends on it until you say so. IDs D-1 to D-16 are those already used in the specification documents; D-17 to D-24 were added by the source-control task; D-25 to D-28 were added by the calculation-engine design (2026-10-11).

## Summary

| ID | Topic | Recommended default | Approval needed |
|---|---|---|---|
| D-1 | Category placement for items listed in several groups | One canonical category plus tags | YES |
| D-2 | Display of out-of-stock or expired prices | Show with a clear label until review date, then "outdated" | YES |
| D-3 | Forged verification stamps: discard or reject | Keep discarding (current behaviour) | YES |
| D-4 | Multi-supplier orders and delivery | Separate order, shipment and fee per supplier | YES |
| D-5 | Cancellation, return, refund policy | Configurable per goods type; none promised until set | YES |
| D-6 | Admin role split | Split into four roles before finance features | YES |
| D-7 | Tax display and rates | Decide per country; show clearly whether tax is included | YES |
| D-8 | First commercial units to support | Smallest verified set; rest added as data | YES |
| D-9 | Auto-confirmation of delivery | No auto-confirmation at first | YES |
| D-10 | Who may deliver | Supplier-arranged only first | YES |
| D-11 | Approved cash policies and deposits | One COD policy, no deposits, at launch | YES |
| D-12 | First payment methods and provider | Cash policy first; online provider later after verification | YES |
| D-13 | Trades model vs `provider_type` | Keep enum as account class; add trades as data | YES |
| D-14 | Company registration details | Voluntary at first | YES |
| D-15 | Review timing, moderation, dispute holds | Completed jobs only; hold during open disputes | YES |
| D-16 | Quoting without a site visit | Allowed unless the trade is flagged site-visit-first | YES |
| D-17 | Price model: evolve `product_prices` or add offers table | New offers table; keep `product_prices` unchanged until migrated | YES |
| D-18 | Attribute validation mechanism | Database-enforced definitions with server checks | Recommended, not blocking |
| D-19 | Platform-coordinated delivery | Not offered initially | YES |
| D-20 | Concurrency test method | Scripted multi-connection harness on a disposable database | Recommended |
| D-21 | Audit coverage for catalog and price edits | Audit all admin edits to catalog, prices, policies | Recommended |
| D-22 | Repository identity, visibility and branching | Private repo, `main` protected, short-lived branches | YES |
| D-23 | Migration deployment ownership | One session or person applies migrations at a time | YES |
| D-24 | Reports and binary files in the repository | Keep specs and migrations in git; store reports under `docs/reports/` | Minor |
| D-25 | First calculation work items | Tiling, slab volume, wall area, paint quantity | YES |
| D-26 | Who approves calculation assumption values | A named qualified reviewer; every value sourced | YES |
| D-27 | Professional review inside the platform at launch | Not at launch; design for it | YES |
| D-28 | Where the authoritative calculation runs | Server-side, same shared package as clients | Recommended |

## Decisions

### D-1: Category placement for items listed in several groups
- **Question:** Items such as insulation, waterproofing and adhesives appear in more than one group. Is a product in one category or several?
- **Recommended default:** One canonical category per product, plus a tag mechanism for cross-references.
- **Alternatives:** (a) Multiple categories per product. (b) Duplicate products per category.
- **Benefits and risks:** One category keeps price history and search results unified and avoids duplicate listings. Multiple categories are flexible but risk inconsistent attributes and split price history; duplicates are worst for data quality.
- **Database effect:** Single `category_id` stays; add a tags table. Option (a) needs a join table and revised attribute rules.
- **Effect on parties:** Customers find items by tag or category; suppliers list once.
- **Approval:** YES, before the catalog seed.

### D-2: Out-of-stock and expired price display
- **Question:** Does a price stay publicly visible when availability is out_of_stock or its review date has passed?
- **Recommended default:** Visible with an explicit label until the review date, then labelled outdated; hidden only when the product is inactive or the supplier is not eligible.
- **Alternatives:** (a) Hide out-of-stock prices. (b) Hide expired prices after a grace period.
- **Benefits and risks:** Showing labelled prices preserves comparison history but may mislead if labels are overlooked. Hiding reduces confusion but removes market information and may look like missing coverage.
- **Database effect:** Visibility rule in the price policy and view; needs `review_by` for expiry (not yet present).
- **Effect on parties:** Customers see what is not available; suppliers may prefer hiding.
- **Approval:** YES.

### D-3: Forged verification stamps (`verified_by`, `verified_at`)
- **Question:** When a supplier submits forged verification fields, should the database discard them silently or raise an error?
- **Recommended default:** Keep current behaviour: accept the row, discard the stamps, and verify that the stored row carries none (tested).
- **Alternatives:** Reject with an error (more visible, may break clients that send the whole row); discard and also write an audit event.
- **Benefits and risks:** Discard is safe and tolerant. Rejecting makes attempts visible to client developers. Neither lets a supplier verify its own price. Adding an audit event helps detect abuse.
- **Database effect:** None for discard. Reject or audit-on-forgery would need a trigger change (a small migration).
- **Effect on parties:** None visible to customers; suppliers' clients behave differently on error.
- **Approval:** YES (no change made).

### D-4: Multi-supplier orders and delivery
- **Question:** May products from different suppliers share one order, delivery or fee?
- **Recommended default:** One order per supplier, separate shipment and fee, unless a supplier explicitly agrees to combine.
- **Alternatives:** One combined order with split fulfilment; platform-coordinated consolidation.
- **Benefits and risks:** Separate orders match real fulfilment and accountability. Combined checkout is easier for customers but complicates payments, disputes and refunds.
- **Database effect:** `orders` keyed per supplier; optional order group for display.
- **Effect on parties:** Customers pay multiple delivery fees; suppliers keep control of their own deliveries.
- **Approval:** YES.

### D-5: Cancellation, return and refund policy
- **Question:** What are the rules, per goods type (standard, made-to-order, bulk, hired machinery)?
- **Recommended default:** Policies stored as configuration per goods type; no refund or return promise displayed until a policy is set.
- **Alternatives:** One platform-wide policy; supplier-defined policies within platform limits.
- **Benefits and risks:** Per-type configuration fits very different goods. A single policy is simple but wrong for bulk materials and machinery. Supplier-defined policies need minimum standards. Consumer-protection law may apply: qualified legal advice recommended.
- **Database effect:** Policy tables, case and refund states, evidence storage.
- **Effect on parties:** Customers, suppliers and delivery all depend on these rules.
- **Approval:** YES.

### D-6: Administrator role split
- **Question:** Keep a single `PLATFORM_ADMIN` role or split into catalog admin, price verifier, support and dispute agent, finance reconciler?
- **Recommended default:** Split into four roles before any financial or dispute feature is built; existing admin keeps all until then.
- **Alternatives:** Keep one role; add permissions as a configurable matrix.
- **Benefits and risks:** Splitting limits exposure of financial and customer data. It adds administration and migration work (changes to the role enum and all policies that call the admin helper). A permission matrix is flexible but heavier.
- **Database effect:** Extend `app_role` or add a permissions table; update policies and tests.
- **Effect on parties:** Mainly internal; affects who can see payment data and resolve disputes.
- **Approval:** YES.

### D-7: Tax display and rates
- **Question:** Are prices shown inclusive or exclusive of tax, and which taxes apply in each country?
- **Recommended default:** Decide per country; show clearly whether tax is included; store tax rules as configuration.
- **Alternatives:** Always exclusive; always inclusive.
- **Benefits and risks:** Wrong display can mislead customers and may have legal consequences (qualified advice recommended). Rates are local data that must be verified.
- **Database effect:** Tax configuration tables; price and order fields indicating tax basis.
- **Effect on parties:** Customers see totals; suppliers need invoicing alignment.
- **Approval:** YES.

### D-8: First commercial units to support
- **Question:** Which units first (bags, per hundred or thousand, marla and similar) and how are they defined?
- **Recommended default:** Start with the smallest verified set needed for the launch categories; add others as data with a stated base and source.
- **Alternatives:** Large unit list from the outset.
- **Benefits and risks:** A small set limits wrong conversions. A large unverified list risks incorrect values.
- **Database effect:** Units registry and conversion rows (not yet built).
- **Effect on parties:** Suppliers enter prices in familiar units; customers see conversions only where a rule exists.
- **Approval:** YES, plus verified definitions from you or suppliers.

### D-9: Auto-confirmation of delivery
- **Question:** Does a delivery become "confirmed" automatically if the customer does not respond?
- **Recommended default:** No auto-confirmation at first; unconfirmed deliveries go to a review queue.
- **Alternatives:** Auto-confirm after a set period; confirm only by delivery code.
- **Benefits and risks:** Auto-confirmation helps suppliers get paid but can harm customers who did not receive goods. Manual queues need staff time.
- **Database effect:** Delivery state machine and a scheduled job if adopted.
- **Effect on parties:** Customers, suppliers, payments (cash reconciliation).
- **Approval:** YES.

### D-10: Who may deliver
- **Question:** Supplier only, third-party transporters, or a platform fleet?
- **Recommended default:** Supplier-arranged delivery only at first.
- **Alternatives:** Registered transport providers; platform-coordinated delivery.
- **Benefits and risks:** Supplier-only is simplest. Third parties and platform fleets add licensing, insurance and liability questions (qualified legal advice recommended).
- **Database effect:** Delivery provider entity and assignment if adopted.
- **Effect on parties:** Delivery responsibility, damage claims, fees.
- **Approval:** YES.

### D-11: Approved cash policies and deposits
- **Question:** Which cash policies are allowed, who confirms collection, and are deposits allowed?
- **Recommended default:** One COD policy for supplier-delivered orders, collected by the supplier, acknowledged by the customer in-app, no deposits, no platform handling of funds.
- **Alternatives:** Deposits via bank transfer; platform-held funds.
- **Benefits and risks:** The simple policy avoids holding customer money (and likely licensing questions). It gives weaker protection against non-delivery. Platform-held funds improve protection but have regulatory implications (qualified advice recommended).
- **Database effect:** Payment policy, cash collection and reconciliation records.
- **Effect on parties:** Customers, suppliers, delivery staff, finance reconciliation.
- **Approval:** YES.

### D-12: First payment methods and provider
- **Question:** Which methods in Pakistan first, and which provider if online?
- **Recommended default:** Cash policy (D-11) first. Online provider only after you select one and its current terms, API, callbacks and sandbox have been verified.
- **Alternatives:** Bank transfer first; online provider first.
- **Benefits and risks:** Cash needs no integration but needs reconciliation. Online payments add cost, compliance and integration risk; availability and terms must be checked at the time.
- **Database effect:** Payment abstraction supporting several providers; provider-specific data kept separate.
- **Effect on parties:** All.
- **Approval:** YES.

### D-13: Trades model versus `provider_type`
- **Question:** How should the roughly 25 trades be modelled?
- **Recommended default:** Keep `provider_type` as the broad account class and add trades as data linked to providers.
- **Alternatives:** Extend the enum with every trade (simple, but changes require migrations); retire the enum.
- **Benefits and risks:** Keeping the enum preserves tested verification and publishing rules. Extending the enum is quick but inflexible. Retiring it is clean but touches many policies.
- **Database effect:** New `trades` and `provider_trades` tables.
- **Effect on parties:** Professionals can be listed in several trades; admins manage trades without code changes.
- **Approval:** YES.

### D-14: Company registration details
- **Question:** Which company registration fields are required versus voluntary?
- **Recommended default:** Voluntary at first; verification decides what is displayed.
- **Alternatives:** Required for companies.
- **Benefits and risks:** Voluntary lowers onboarding friction; required improves trust but excludes small businesses. Requirements vary by country (DATA, qualified advice recommended).
- **Database effect:** Company fields and documents; nullable columns.
- **Effect on parties:** Companies and their customers.
- **Approval:** YES.

### D-15: Reviews: timing, moderation and dispute holds
- **Question:** When can a review be posted, how is it moderated, and what happens during a dispute?
- **Recommended default:** Only after a completed job, one per job, moderation states, and hold while a dispute is open.
- **Alternatives:** Allow reviews at any time after contact; no moderation.
- **Benefits and risks:** The default resists fake reviews but delays feedback. Looser rules risk manipulation.
- **Database effect:** Reviews table tied to completed orders or bookings; moderation status.
- **Effect on parties:** Providers and suppliers (reputation), customers.
- **Approval:** YES.

### D-16: Quoting without a site visit
- **Question:** May providers quote without visiting the site?
- **Recommended default:** Allowed unless the trade is flagged site-visit-first; quotes can be marked provisional.
- **Alternatives:** Site visit always required; never required.
- **Benefits and risks:** Provisional quotes speed up comparison but may change. Mandatory visits slow customers.
- **Database effect:** Trade flag and quote status (provisional).
- **Effect on parties:** Customers and professionals.
- **Approval:** YES.

### D-17: Price model evolution
- **Question:** Extend `product_prices` (variants, tiers, effective dates, several sale units) or create a new offers structure?
- **Recommended default:** New offers structure; keep `product_prices` and its tested rules untouched until a reviewed migration path exists.
- **Alternatives:** Alter `product_prices` in place; run both in parallel.
- **Benefits and risks:** A new structure avoids rewriting tested behaviour but means migrating data later. In-place change reuses existing tests but risks regressions in security rules. The current unique index allows only one row per product, city, area and supplier.
- **Database effect:** New tables or revised uniqueness; history coverage extended.
- **Effect on parties:** Suppliers can list several pack sizes and bands; customers see accurate per-unit prices.
- **Approval:** YES.

### D-18: Attribute validation mechanism
- **Question:** Where is category-specific attribute validation enforced?
- **Recommended default:** Attribute definitions in the database, enforced by database validation, with server checks for friendly errors.
- **Alternatives:** Application-only validation; JSON schema stored per category.
- **Benefits and risks:** Database enforcement protects every client; it is more work and harder to evolve. App-only validation is faster but unsafe.
- **Database effect:** Definition tables and validation functions.
- **Effect on parties:** Data quality for all.
- **Approval:** Recommended; not blocking.

### D-19: Platform-coordinated delivery
- **Question:** Will the platform itself coordinate deliveries?
- **Recommended default:** Not offered initially.
- **Alternatives:** Offer through partners; offer in selected cities.
- **Benefits and risks:** Not offering avoids operational and liability burden; offering adds a service customers may value. Depends on D-10.
- **Database effect:** Delivery provider and assignment records.
- **Effect on parties:** Customers, suppliers, delivery partners.
- **Approval:** YES.

### D-20: Concurrency test method
- **Question:** How will concurrent writes be tested?
- **Recommended default:** Scripted multi-connection harness on a disposable local or branch database, not on the production project.
- **Alternatives:** Supabase branch database; test in production (not recommended).
- **Benefits and risks:** A disposable database is safe; it needs setup. Testing in production risks data and is not advised.
- **Database effect:** None.
- **Effect on parties:** None directly.
- **Approval:** Recommended.

### D-21: Audit coverage for catalog and price edits
- **Question:** Should catalog, price and policy edits be written to the audit log?
- **Recommended default:** Yes for admin edits to catalog, prices and policies, and all financial events.
- **Alternatives:** Audit only security-relevant events; rely on price history alone.
- **Benefits and risks:** Wider audit aids disputes and investigations; it increases storage and trigger load.
- **Database effect:** Additional triggers and audit event types.
- **Effect on parties:** Mostly internal; strengthens dispute handling.
- **Approval:** Recommended.

### D-22: Repository identity, visibility and branching
- **Question:** Which GitHub repository holds the project, and how is it organised?
- **Recommended default:** One private repository named for the product, `main` protected, short-lived feature branches, review before merge. If no project repository exists yet, you create it (or authorise one) and I do not create a duplicate.
- **Alternatives:** Reuse an existing repository; separate repositories for app and database.
- **Benefits and risks:** A single private repository keeps migrations and application together. Public visibility would risk exposing project references and internal documents.
- **Database effect:** None.
- **Effect on parties:** Development workflow only.
- **Approval:** YES. I need the exact repository owner and name, or confirmation that none exists yet.

### D-23: Migration deployment ownership
- **Question:** Who or what may apply migrations?
- **Recommended default:** Exactly one session or person applies migrations at a time, always from a committed file, with the hash comparison repeated afterward.
- **Alternatives:** Automated deployment from the main branch after review.
- **Benefits and risks:** Single ownership avoids the parallel-application problem seen earlier with migration 0002. Automation adds speed but needs reliable review and rollback.
- **Database effect:** None.
- **Effect on parties:** Development workflow.
- **Approval:** YES.

### D-24: Reports and binary files in the repository
- **Question:** Should Word and Excel reports be committed?
- **Recommended default:** Commit specifications and migrations as text; keep the security reports under `docs/reports/` as historical records, with the BuildMart-titled original marked historical.
- **Alternatives:** Keep reports outside the repository.
- **Benefits and risks:** Committing keeps evidence together; binaries do not diff well.
- **Database effect:** None.
- **Effect on parties:** None.
- **Approval:** Minor.

### D-25 to D-28: Calculation engine decisions
Full context in `CALCULATION_ENGINE_SPEC.md`, Section 13.
- **D-25 First work items.** Recommended: tiling, slab volume, wall area, paint quantity (they need only geometry and few sourced parameters). Alternatives: start with concrete constituents (needs a sourced mix assumption set and engineer review). Database effect: formula module registry and assumption keys. Affects customers and suppliers by what the estimate covers. Approval: YES.
- **D-26 Assumption approval.** Recommended: every assumption value needs a source and a named qualified approver. Alternatives: admin-entered values with source only. Risk of weaker approval: wrong estimates and liability. Database effect: approver and validity fields. Approval: YES.
- **D-27 Professional review in platform.** Recommended: not at launch; keep the record design ready. Alternatives: offer paid review from verified engineers. Needs liability and licensing review (qualified legal advice recommended). Approval: YES.
- **D-28 Where the calculation runs.** Recommended: server-side authoritative run using the same shared package as clients. Alternatives: database functions; client-only. Database functions are hard to test and version; client-only runs are not trustworthy for quotes. Approval: recommended, not blocking.
