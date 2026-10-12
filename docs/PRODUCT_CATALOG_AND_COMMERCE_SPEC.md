# My Construction Platform: Product Catalog and Commerce Specification

Status: SPECIFICATION ONLY (v0.1, 2026-10-10). Nothing in this document has been built unless Section 2 says so.
No migration is created or applied by this task. Where a detail is unknown, the document records a decision to be made and keeps the value configurable. No prices, suppliers, brands or local-market figures are invented here.

Related documents: `DELIVERY_AND_PAYMENT_SPEC.md`, `PROFESSIONAL_SERVICES_SPEC.md`, `ACCEPTANCE_TEST_MATRIX.md`, `../ARCHITECTURE.md`.

## 1. Gap-analysis legend

| Tag | Meaning |
|---|---|
| IMPLEMENTED | Exists in the live database (project trjrkzkpdilgyfuogfba) and was exercised by the executed tests recorded in the 0005 report |
| PARTIAL | A related structure exists but does not cover the requirement |
| MISSING | Planned, nothing exists |
| DECISION | Needs a business or policy decision before design is final |
| DATA | Needs verified local-market data before it can be populated |

## 2. Gap analysis against the existing schema

The live schema was read on 2026-10-10. Public tables: `areas, audit_logs, brands, cities, countries, material_categories, platform_settings, price_history, price_sources, product_prices, products, profiles, provider_profiles, regions, user_roles, verification_documents, verification_events, verification_requests`, plus the view `product_prices_view`. Enums: `app_role` (10 values), `price_source_type` (admin_entry, supplier, api, survey, model_estimate, seed_demo), `price_status` (verified, supplier_submitted, estimated, historical, demo), `provider_type` (CONTRACTOR, ENGINEER, ARCHITECT, DRAFTSMAN, WORKER, SUPPLIER, MACHINERY_PROVIDER), `verification_doc_type`, `verification_status`.

| Requirement | Tag | What exists / what is missing |
|---|---|---|
| Geography Country > Province/State > City > Area | IMPLEMENTED | `countries, regions, cities, areas` with composite FKs and `name_i18n`. No locality level below area. |
| Categories with sub-categories, admin-managed, localizable, deactivatable | IMPLEMENTED | `material_categories` has `parent_id, name_i18n, is_active, sort_order, default_unit`. Not exercised for deep hierarchies; no cycle guard recorded. |
| Brands | PARTIAL | `brands(id, slug, name, created_at)`. Missing: `is_active`, `updated_at`, `name_i18n`, logo, manufacturer, country of origin. |
| Products with category-specific specification | PARTIAL | `products` has `category_id, brand_id, slug, name, model, specification jsonb, unit, is_active`. No SKU, description, images, packaging, MOQ, warranty, documentation. `specification` is free-form jsonb with no per-category validation. |
| Variants (size, grade, colour) | MISSING | No variant table. A product carries one `unit`. |
| Category-specific attribute definitions and validation | MISSING | No attribute-definition tables. |
| Units and conversions | MISSING | `unit` is plain text on products and prices. There is no unit registry or conversion table. The price trigger only requires `price.unit = product.unit`. |
| Price states (5) with source and verification metadata | IMPLEMENTED | `price_status`, `price_source_type`, `source_id`, `source_note`, `verified_at/by` with constraints `verified_needs_stamp`, `demo_source_matches`. |
| Supplier price cannot self-verify | IMPLEMENTED | Tested (SS3/SS4 and variants). Forged verified stamps are discarded, not rejected (decision pending). |
| Immutable price history | IMPLEMENTED | `price_history` append-only (update/delete/truncate blocked, tested). |
| Price visibility tied to verification, publication, suspension, availability | IMPLEMENTED | Tested matrix A to H. Note: `availability` (in_stock, limited, out_of_stock, unknown) does not hide a price; only product `is_active` does. Whether out-of-stock prices should be shown is a DECISION. |
| One price per product, city, area, supplier | IMPLEMENTED | Unique index `product_prices_unique_idx`. This also means: no second price for a different packaging, quantity band, delivery method or effective date. |
| Quantity tiers, bulk discounts | MISSING | Needs a rule table (see 5.3). |
| Effective date, expiry or review date on prices | MISSING | Only `created_at/updated_at`. Freshness is derived from `updated_at` and the `price_stale_days` setting. |
| Price per delivery destination / method / order size | MISSING | See Delivery spec. |
| Taxes and fees | MISSING + DECISION | Tax regime and rates require local verification (DATA). |
| Supplier profile (SUPPLIER provider type) | PARTIAL | `provider_profiles` with `attributes jsonb`. No supplier-specific fields (delivery zones, payment terms, business registration number). |
| Product images, logos, documents | MISSING | No columns. `0006_storage.sql` is written but NOT applied. |
| Stock tracking | MISSING | Only coarse `availability` text on prices. No quantity. |
| Quote requests, quotations, items | MISSING | Not created. |
| Cart, orders, order items | MISSING | Not created. |
| Delivery, payments, disputes, returns | MISSING | Not created. |
| Roles for admins, suppliers, customers | IMPLEMENTED | `app_role`, `private.has_role/is_admin`, role self-assignment blocked for admin roles. |
| Audit trail for verification, roles, suspension | IMPLEMENTED | `audit_logs` via triggers. Not yet covering catalog edits, price edits, orders or payments. |
| English / Urdu / Arabic content | PARTIAL | `name_i18n` exists on geography and categories only. |
| Search | MISSING | No full-text or trigram indexing. |

Not implemented anywhere: any web or mobile application. There is no app code in the project folder.

## 3. Catalog structure

### 3.1 Taxonomy
Nine top-level groups (A to I in the product brief) are seeded as **data**, not code. Sub-categories are children of a category through `parent_id`. The brief lists some items under more than one group (Insulation appears in G and I; Waterproofing in B, E and G; Adhesives in B and I). Decision needed (DECISION D-1): one canonical category per item with cross-reference tags, or allow a product in several categories. Recommendation: one canonical category plus a `tags` mechanism, to avoid duplicate listings and split price history.

Seeding the taxonomy requires approval of the category list; `seed.sql` currently contains 14 flat categories only and is not applied.

### 3.2 Entity model (proposed, not built)

| Entity | Purpose | Key fields (summary) |
|---|---|---|
| `product_families` (optional) | Group variants of one item (a tile range, a cement brand line) | category, brand, name, description, origin_country |
| `products` (extend) | Sellable item or base item | existing fields + sku, description, packaging, moq, warranty_months, status |
| `product_variants` | A concrete sellable combination | product_id, sku, attributes (validated), base_unit, original_supplier_unit |
| `attribute_definitions` | Which fields a category's products carry | category_id, key, label_i18n, data_type, unit_dimension, required, allowed_values, min, max |
| `units` | Registry of units | code, dimension (length, mass, volume, area, count, time, load), symbol, name_i18n |
| `unit_conversions` | Explicit tested conversion rules | from_unit, to_unit, factor, scope (global, category or material-specific), source, verified_by |
| `product_media` | Images and documents | owner, kind, storage_path, public/private flag |
| `supplier_offers` (or evolution of `product_prices`) | A supplier's offer for a variant in a location | see Section 5 |

Typed columns for fields every product has (name, brand, unit, status); validated structured attributes for category-specific fields. The attribute definitions drive both the validation (server side, in database constraints or validation functions) and the form UI.

### 3.3 Category-specific attributes (to be encoded as `attribute_definitions` rows, not columns)

Fields below come directly from the product brief. Values (allowed grades, sizes, brands) are DATA and must be confirmed by suppliers or verified sources for each market.

| Family | Required structured attributes | Notes |
|---|---|---|
| Tiles | type, length, width, thickness, dimension unit, finish, colour/pattern, material, grade, indoor/outdoor, tiles per box, coverage per tile, coverage per box, packaging | Coverage per box may be derived from dimensions x tiles per box; when supplier-stated and derived values disagree, keep the supplier value and flag. Price per tile, box and area are separate offer fields. Wastage allowance is configurable and off by default. |
| Gravel / crush | aggregate category, supplier-stated size or range, size unit, gradation, stone type, origin, quality description | Store the supplier's own size label and unit. Do not map labels such as 3/8 or 1/2 inch to a standard unless a verified rule exists. |
| Cement | brand, type, grade/specification, bag weight, packaging, batch details only if supplied | Never display manufacturing or expiry dates unless supplied. |
| Steel / rebar | brand, product type, nominal diameter and its unit, grade, bar length, weight per bar if specified, bundle details | Keep diameter, length, mass and commercial label as separate fields; never infer dimensions from a marketing label. |
| Bricks / blocks | material, supplier dimensions, quality description, solid/hollow | Sold per piece, per hundred or per thousand. |
| Pipes | material, diameter, length, pressure class | Fittings are separate products. |
| Cables | conductor material, cross-section/gauge, length, insulation | |
| Paint | type, volume, colour code, finish, coverage statement, pack size | Coverage is a supplier statement, stored as such. |
| Doors / windows | height, width, thickness, material, hardware | |
| Sanitary | dimensions, fitting type, material, warranty | |
| Tools (tape measures etc.) | blade length, blade width, graduation units, material, case type | |
| Machinery | model, operating capacity, location, rental period, operator included, fuel terms | See Delivery and Professional specs for rental. |

Every family also carries the common fields in the brief (SKU, description, origin where known, packaging, MOQ, stock where tracked, warranty, documentation, images, availability, status, supplier, last update). Unknown values stay NULL; the UI shows "not provided", never a default.

## 4. Units and conversions

Rules (all DECISION-free except the data):

1. Every quantity carries an explicit unit code from the `units` registry. Free-text units are not allowed in new tables.
2. The supplier's original unit and quantity are always stored and shown.
3. Conversions happen only through `unit_conversions` rows. Each row has a scope: `global` (for example metres to feet, exact), `category`, or `material` (for example volume to mass, which needs a density).
4. Volume to mass and vehicle-load conversions are never global. They require a documented material-specific density or a supplier-confirmed conversion, recorded with source and date (DATA).
5. A conversion that has no rule returns "cannot convert", not a guess.
6. Exact conversions (length, area, mass among standard units) are covered by unit tests with fixed expected values. Regional commercial units (for example marla, kanal, bag sizes, "per hundred" or "per thousand") are defined as data with a stated base and must be confirmed (DATA).
7. Rounding rules are stored per unit dimension. Money uses `numeric`, never floating point.

Current state: nothing above exists. The only unit check today is that a price's unit equals its product's unit.

## 5. Pricing engine

### 5.1 What exists
One current-price row per (product, city, area, supplier), a five-state status, source metadata, `previous_price` maintained by trigger, append-only history on price or status change, and a public view that labels prices (Verified, Verified (outdated), Supplier submitted, Supplier submitted (outdated), Estimate, Historical price, Demo data). The word "live" is never used.

### 5.2 Extensions required for the brief (not built)
Dimensions the brief asks for and what each needs:

| Price dimension | Proposed handling |
|---|---|
| Supplier, city, area, country | Already present. Province/state is reachable through city. |
| Variant, brand, grade, specification | Price attaches to a variant, not only a product. |
| Unit, packaging | A price states its sale unit and pack; one variant may have several sale units (per tile, per box, per area). Today's unique index allows only one row per location and supplier, so this needs a revised uniqueness rule. |
| Quantity, order size | Quantity-band rules (5.3). |
| Delivery destination and method | Not part of the base price. Delivery is a separate quoted or rule-based charge (Delivery spec). |
| Offer or discount | Offer table with start, end, conditions, created by an authorised actor. |
| Effective date, expiry or review date | Add `effective_from`, `review_by` (nullable). Freshness rules use them where present. |
| Tax and fees | Configurable per country and category. Rates are DATA and a DECISION on whether prices display inclusive or exclusive of tax. |

### 5.3 Quantity and bulk-discount rules
A `price_tiers` rule belongs to one offer and has `min_qty`, `max_qty`, unit, and either a unit price or a discount. Rules:
- Calculated only from stored, authorised rules, owned by the offering supplier and visible only when the parent offer is visible.
- Bands may not overlap; enforced by constraint.
- A calculation records which rule version produced the number.
- A supplier's tiers cannot be marked verified by the supplier.

### 5.4 Status and trust rules (carried over, unchanged)
- Supplier-submitted prices never become verified automatically.
- Only administrators (or a documented verification procedure) set `verified`.
- A price older than the stale threshold shows as outdated.
- Placeholders, demo and historical prices are never labelled current verified market prices.
- Public visibility requires: active product, and for supplier prices a verified, published, non-suspended supplier.
- Open decision D-2: should an out-of-stock or expired price remain publicly visible with a label, or be hidden? Recommendation: visible with a clear label until its review date, then labelled outdated.
- Open decision D-3: should forged verified stamps raise an error instead of being discarded? Current behaviour (discard) is safe and is preserved unless you decide otherwise.

### 5.5 Price history
Keep the current append-only history for price and status changes. Extend (when built) to cover tier, offer and effective-date changes. History rows must never be edited or removed.

## 6. Cart, orders and checkout

Quotation request and confirmed order are different records with different tables. An inquiry, a quotation, or an accepted estimate is never a paid or confirmed transaction.

### 6.1 Flow
Browse > variant > quantity > supplier > delivery destination > delivery option > price summary > payment option > order confirmation > delivery tracking > completion > review.

### 6.2 Model (proposed, not built)
- `carts` and `cart_items`: private to the customer, holding variant, supplier offer, quantity, unit, and the price snapshot shown. Items from different suppliers stay in separate supplier groups; a cart can hold several.
- `orders`: one order per supplier. Different suppliers never share a delivery fee or shipment unless a supplier explicitly agrees (DECISION D-4).
- `order_items`: quantity, unit, unit price, and the price status at confirmation time. Totals are computed server-side from stored rules.
- `order_status_events`: append-only record of every state change with actor and timestamp.

### 6.3 Revalidation before confirmation
At confirmation, the server rechecks: the offer still exists and is visible, the price has not changed (or the customer accepts the new price), the quantity meets the minimum order and unit rules, stock is not known to be insufficient, and the delivery quote (if any) is still valid. Any mismatch blocks confirmation and shows what changed.

### 6.4 Order states (proposed)
Draft > Awaiting supplier confirmation > Confirmed > In fulfilment > Partially fulfilled > Fulfilled > Completed; and exceptions: Cancelled, Disputed, Return requested, Refunded (financial states are in the Payment spec). Allowed transitions are enforced by a database function, with each transition restricted to named actors.

### 6.5 Rules
- Duplicate prevention: an idempotency key per submission so a double click or retry cannot create two orders.
- Cancellation, partial fulfilment, return and dispute rules are policy and must be configured before they are shown to customers (DECISION D-5). Different rule sets for standard merchandise, made-to-order goods, bulk materials and hired machinery.
- Order history and receipts are generated from stored records only. A receipt for an unpaid order must say so.

## 7. Quotations (summary)
Detailed state model is in `PROFESSIONAL_SERVICES_SPEC.md` (Section 6), shared by goods and services. For materials the flow is: requirement > supplier selection > quote request > supplier response > compare > accept > confirm order. Accepting a quotation creates an order proposal that the customer still confirms; acceptance alone does not take payment.

## 8. Admin controls

Planned admin areas: categories, attribute definitions, brands, products, variants, units and conversions, price verification, supplier approvals, delivery zones, vehicle and transport options, shipping fee rules, COD eligibility, cash collection confirmation, payment reconciliation, cancellations and returns, disputes and refunds, professional trades, service pricing rules, quotations, orders and projects, notifications, reviews, reports, audit logs.

Principles:
- Role-based: separate roles for catalog admin, price verifier, support and dispute agent, finance reconciler. Today there is one admin role (`PLATFORM_ADMIN`); splitting roles is a DECISION (D-6). Finance data must not be readable by roles that do not need it.
- Every admin change to catalog, price, policy and financial records writes an audit event.
- Users cannot grant themselves admin roles or approve their own verification (IMPLEMENTED and tested for roles and verification).

## 9. Localization and geography
- Names and descriptions stored with `*_i18n` jsonb for English, Urdu and Arabic. Brands, products, attribute labels and units must gain this (MISSING).
- Right-to-left layout is a UI requirement (no UI exists).
- Currency is stored per country (`default_currency`) and checked on prices (IMPLEMENTED); future markets add data, not code. Pakistan-specific assumptions (units like bag sizes, tax, payment methods) live in configuration rows, not in the schema core.
- Dates stored as `timestamptz`; display uses the country's time zone.

## 10. UI requirements (planning)
Screens: home, search, categories, product variants, product details, price comparison, supplier profile, cart, checkout, delivery options, order tracking, payment status, quotation requests and comparison, services marketplace, provider profiles, booking, project progress, messages, notifications, saved items, reviews, customer account, supplier dashboard, professional dashboard, delivery management, admin dashboard, help and disputes.

Every screen defines: loading, empty, error, permission-denied and success states. No button may imply a transaction that does not exist. Screens that depend on unbuilt tables are not shipped as working screens.

## 11. Recommended implementation sequence
Each step is a vertical slice (database, policy, API, UI, tests) and needs approval before any migration.

1. Source control baseline (blocked on GitHub reconnection).
2. Review and, if approved, apply storage (0006) and foundational seed, as already planned.
3. Catalog core: schema additions for brand/product fields, units registry, attribute definitions (smallest version for 2 or 3 categories first), with tests.
4. Variants and offer pricing: variants, revised price uniqueness, effective/review dates, tiers.
5. Minimal customer app: browse categories, product list, details, supplier details (real queries only).
6. Quote requests and supplier quotations (goods).
7. Delivery quotation (supplier-quoted first, rule-based later).
8. Orders and cash-on-delivery under an approved policy.
9. Professional services marketplace and service quotes.
10. Disputes, returns and refunds.
11. Online payment integration, only after verified provider integration.

## 12. Decisions requiring your input

| ID | Decision |
|---|---|
| D-1 | One canonical category per product vs multi-category listing |
| D-2 | Display rules for out-of-stock and expired prices |
| D-3 | Discard vs reject forged verification stamps |
| D-4 | Whether orders from different suppliers may combine delivery |
| D-5 | Cancellation, return and refund policies per goods type |
| D-6 | Admin role split (catalog, price verifier, support, finance) |
| D-7 | Tax display: inclusive or exclusive; applicable taxes by country |
| D-8 | Commercial units to support first (bags, per thousand, marla and similar) and their definitions |

## 13. Data requiring verified local-market sources
Brand and manufacturer lists; real product ranges and specifications; permissible grades and size labels; commercial packaging; densities for volume-to-mass conversion; vehicle load capacities; delivery zones and coverage; tax rates; any price. None of these are entered by this specification, and none may be entered as current verified data without a source and approval.
