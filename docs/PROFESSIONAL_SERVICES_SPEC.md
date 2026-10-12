# My Construction Platform: Professional and Labour Services Specification

Status: SPECIFICATION ONLY (v0.1, 2026-10-10). Nothing in Sections 3 to 8 is built unless Section 1 says so. No rates, qualifications or licensing rules are invented here; all are configuration or verified local data.

Related: `PRODUCT_CATALOG_AND_COMMERCE_SPEC.md`, `DELIVERY_AND_PAYMENT_SPEC.md`, `ACCEPTANCE_TEST_MATRIX.md`.

## 1. Gap analysis

Tags as defined in the catalog spec (IMPLEMENTED, PARTIAL, MISSING, DECISION, DATA).

| Requirement | Tag | Status against the live schema |
|---|---|---|
| Provider profiles for professionals | IMPLEMENTED | `provider_profiles` with `provider_type`, `display_name`, `headline`, `description`, `years_experience`, `city_id`, `area_id`, `phone`, `whatsapp`, `daily_rate`, `hourly_rate`, `currency`, `availability`, `attributes jsonb`, `verification_status`, `is_published`. |
| Verification workflow, documents, audit | IMPLEMENTED | Tested: pending > under_review > verified or rejected, revocation, only verified providers can be published, suspension unpublishes. Documents table exists; the storage bucket policy (0006) is NOT applied. |
| Trades beyond the 7 provider types | MISSING | Enum `provider_type`: CONTRACTOR, ENGINEER, ARCHITECT, DRAFTSMAN, WORKER, SUPPLIER, MACHINERY_PROVIDER. The brief lists about 25 trades (plumber, electrician, mason, welder, and so on). `WORKER` currently covers all labour. |
| Construction company profiles (members, different semantics) | MISSING | `COMPANY_ADMIN` role exists; no company table. |
| Admin-configurable trades | MISSING | Trades would need to be data, not an enum. |
| Services listed independently of products | MISSING | No services table. |
| Rates by day and hour | PARTIAL | `daily_rate`, `hourly_rate` only. No per-project, per-area, per-item, per-point or per-fixture pricing. |
| Per-trade pricing units | MISSING | Needs the units registry (catalog spec Section 4). |
| Service radius, travel charge, minimum booking, emergency availability | MISSING | |
| Skills, licences, certifications | PARTIAL | Verification document type `certificate` exists; no structured skills or licence records. |
| Portfolio (never fabricated) | MISSING | Needs private-or-public media rules and a moderation status. |
| Reviews from eligible completed work | MISSING | No reviews table. |
| Quote requests and quotations | MISSING | |
| Booking, projects, progress | MISSING | |
| Public listing only for verified, published, non-suspended providers | IMPLEMENTED | Tested visibility matrix on the provider policy and on price visibility. |

## 2. Trades and services model (proposed)

### 2.1 Trades as data
A `trades` table (admin-managed, localizable, activatable) replaces the fixed provider-type list for services. The initial trade list from the product brief is seeded only after approval: contractors, construction companies, civil engineers, architects, draftsmen, plumbers, electricians, masons, general labourers, carpenters, welders, painters, tile installers, marble workers, aluminium and glass workers, roofing and waterproofing specialists, HVAC technicians, solar installers, water-pump technicians, sanitary installers, landscapers, surveyors, machinery providers, transport providers, other admin-configured trades.

Decision D-13: keep `provider_type` as the broad account class (individual professional, company, supplier, machinery or transport provider) and add trade as data, or retire the enum entirely. Recommendation: keep the enum for account class and add a `provider_trades` link table, so existing verification and publishing rules keep working unchanged.

### 2.2 Services
A `provider_services` table lets one provider list several services, each with:
- trade, title, description (localizable),
- pricing method and unit (Section 3),
- rate or "quote required",
- inclusion flags: labour only, or includes materials, transport, tools or equipment,
- minimum booking, estimated duration, travel or call-out charge, emergency availability,
- service area (cities, areas, radius),
- status.

A service is publicly visible only when its provider is verified, published and not suspended, using the same rule as provider and price visibility today.

### 2.3 Profile content
Name or registered business name, role and trade, location and service radius, experience, skills and qualifications, licence or certification where applicable, services, work portfolio, availability, verification status, reviews from eligible completed work, contact preferences, quote request and booking rules.

Fields not relevant to a trade are not forced on it. Trade-specific fields are driven by definitions (same mechanism as product attribute definitions), not by columns.

### 2.4 Companies
A company is a separate entity with members, roles and its own verification, distinct from an individual profile. Needed: `companies`, `company_members`. Business registration details are voluntary unless a DECISION requires them (D-14). Company verification uses the existing verification workflow pattern.

### 2.5 Portfolio and qualifications
- Portfolio items must be supplied by the provider and are never generated or fabricated by the platform. Items carry a moderation status (pending, approved, rejected, flagged, removed).
- Customer-visible portfolio media is public only after approval. Identity and licence documents are always private.
- Qualifications and licences are stored with issuer, number, validity dates and a verification status set only by an administrator. Licensing requirements differ by trade and country (DATA, and qualified legal advice recommended).

## 3. Pricing methods

Supported methods (units configured per trade or service, never one universal rate): per day, per hour, per project, per square foot, per square metre, per item, per installation, per electrical point, per plumbing fixture, per defined service unit.

Rules:
- Each service declares which methods it allows and the unit for each.
- Currency is explicit and matches the country.
- Rates entered by a provider are provider-stated and labelled that way. Platform-estimated rates are labelled estimates. Nothing is shown as a market or verified rate without a source.
- Labour-only and inclusive quotations are distinguished in every quote (Section 6.3).
- Today's `daily_rate` and `hourly_rate` remain valid as simple profile-level rates until services exist.

## 4. Verification and trust

- Verification follows the existing implemented workflow: submit, review, verified or rejected, revocation, audit events. No automatic verification.
- A provider cannot verify itself or alter its verification status; this is enforced and tested today.
- Reviews are accepted only from customers with a completed, eligible booking or order with that provider (review eligibility rule below). No reviews are created by the platform or sold.
- Ranking and sponsored placement follow the project rules: documented signals, sponsored results always labelled, payment never the only factor.

### Review eligibility (proposed)
A review requires a completed booking or order between the reviewer and the provider, one review per completed job, a moderation state, and a reply right for the provider. Disputed jobs are held until resolved (DECISION on timing, D-15).

## 5. Availability and booking
- Availability states today: available, busy, unavailable, unknown (IMPLEMENTED as a profile-level field).
- Booking needs: requested date and window, duration estimate, site address (private), status, cancellation terms. A booking is created only from an accepted quotation or a direct booking the provider's rules allow.
- Site visits: a quote may be conditional on a site visit; the visit is a scheduled step with its own status.
- Calendar-level availability is a later improvement; do not promise availability that is not maintained by the provider.

## 6. Quotations (goods and services)

### 6.1 Entities (proposed)
`quote_requests`, `quote_request_items`, `quotations`, `quotation_items`, `quotation_revisions` (or versioned rows), `quote_events` (append-only).

### 6.2 Quote request
Customer, project reference (optional), location, requirement description, scope items (materials or services), preferred dates, budget (optional, private), recipients (selected providers or suppliers, or eligible matches). Personal details are released to a recipient only as needed and per customer consent.

### 6.3 Quotation content
Provider or supplier, items or services, quantity, unit, rate, line total, notes, validity period, timeline, terms, status. Explicit flags: labour only, or includes materials, transport, tools, equipment, travel, taxes. Totals are computed by the server from the line items; a stored total must always equal the computed one.

### 6.4 States
Draft, Sent, Viewed, Accepted, Rejected, Expired, Cancelled, and additionally Revised (superseded by a newer revision) and Countered (customer counter-offer), per the product brief.

Transitions (proposed):
- Draft > Sent (provider/supplier only).
- Sent > Viewed (recorded when the customer opens it; informational).
- Sent or Viewed > Accepted / Rejected (customer only, before expiry).
- Sent or Viewed > Countered (customer), which opens a new revision for the provider.
- Sent or Viewed > Expired (system, at validity end).
- Draft, Sent, Viewed > Cancelled (provider; customer may cancel a request).
- Accepted quotations cannot be edited. Changes require a new revision and a new acceptance.

### 6.5 Acceptance semantics
Accepting a quotation records agreement to the quoted terms. It is not payment and does not by itself confirm a paid order. For goods it leads to an order the customer still confirms (see catalog spec Section 6); for services it leads to a booking. Both require the revalidation and policy rules in the Delivery and Payment spec.

### 6.6 Comparison
Customers compare quotations side by side with explicit labels for what is and is not included. The comparison never hides inclusions or exclusions, and never ranks by anything other than stated criteria.

## 7. Projects (summary)
A project groups requests, quotations, orders, bookings and messages for one construction job, with configurable stages (not hard-coded) and members with roles. `projects` and `project_members` are MISSING. Stage lists are data. Project membership gives access to project records only through RLS.

## 8. Messaging, notifications, saved items
Not built. Requirements: in-app messaging between parties linked to a request, quotation, booking or order; abuse protection and rate limits; no sharing of phone numbers beyond the owner's contact preferences; notification preferences per user; saved providers and saved products private to the user.

## 9. Admin controls
Trades, service pricing rules, provider approvals and verification review, portfolio moderation, quotations oversight (read access for dispute handling), review moderation, suspensions, audit logs. Role split is decision D-6 in the catalog spec.

## 10. Decisions and data needed

| ID | Item |
|---|---|
| D-13 | Keep `provider_type` for account class and add trades as data? |
| D-14 | Which company registration details are required vs voluntary |
| D-15 | Review timing, moderation and dispute holds |
| D-16 | Whether providers may quote without a site visit for each trade |
| DATA | Trade list approval, licence and certification requirements per trade and country, pricing units per trade, travel and call-out norms |

## 11. Implementation notes
- Build order: trade data and `provider_services`, then quote requests and quotations (goods first, then services), then bookings, then reviews.
- Preserve the existing verification and publishing guarantees; any new public table uses the same rule (verified, published, non-suspended provider).
- Every new table needs RLS and tests for anon, owner, other customer, provider party, other provider, admin.
- No migration is created by this task.
