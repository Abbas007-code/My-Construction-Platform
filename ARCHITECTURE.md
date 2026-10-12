# My Construction Platform: Architecture (v0.1, Phase 0)

Status legend: **[Designed]** = specified here, not yet built. **[Written, untested]** = code exists but has not been run against a real database. Nothing in this document is marked "done" unless it has been executed and tested.

## 1. System architecture
- **Web app:** Next.js (App Router, TypeScript), SSR/ISR for public SEO pages, client components only where interactive. Installable PWA.
- **Backend:** Supabase (Postgres 15+, Auth, Storage, Realtime). Business-critical rules live in the database (constraints, RLS, `SECURITY DEFINER` RPCs) so a future mobile app gets the same guarantees as the website.
- **Server logic:** Next.js Route Handlers / Server Actions for validation, rate limiting, AI calls and third-party webhooks. Supabase Edge Functions only for scheduled/background jobs.
- **Hosting:** Vercel (app), Supabase (data). Source in GitHub, secrets only in Vercel/Supabase env settings.
- **Client rule:** the browser never holds a `service_role` key. Only the publishable (anon) key is public.

## 2. Technology decisions
| Choice | Reason | Lock-in mitigation |
|---|---|---|
| PostgreSQL via Supabase | Relational integrity, RLS, PostGIS/pgvector later | Plain SQL migrations in repo; `pg_dump` export works anywhere |
| Next.js + TypeScript | SSR/SEO, one codebase for web+PWA | Standard React; API logic kept in `lib/` services |
| Zod | Shared server-side validation schemas | Library-agnostic schemas |
| next-intl (planned) | RTL/LTR, ICU messages | Messages are JSON files |
| Vercel | Easy deploys | App is portable to any Node host |

## 3. Database architecture
- Migrations in `supabase/migrations/`, numbered, forward-only. Seed data in `supabase/seed.sql`.
- UUID primary keys, `timestamptz` everywhere, `numeric` for money, enums for closed sets, `jsonb` only for genuinely variable attributes.
- FKs indexed. Composite FKs enforce geography consistency (a price's city must belong to its country).
- **Written in Phase 0 [Written, untested]:** geography, profiles, roles, provider profiles, verification workflow, audit logs, catalog, prices, price history, platform settings.
- **Deliberately deferred to their slices:** leads, quotations, orders, reviews, notifications, saved items, AI conversations, subscriptions, payments, commissions, ads, support tickets, machinery. Adding them now would be speculative design with no workflow to validate it.
- **Provider modelling decision:** one `provider_profiles` table with a `provider_type` enum and a validated `attributes jsonb` for type-specific fields, instead of seven near-identical tables. Companies get their own table in the Quotes/Companies slice because they have members and different semantics.

## 4. Security architecture
Defence in depth: (1) Next.js validates input (Zod) → (2) RPC/route authorizes → (3) Postgres RLS and constraints are the final authority. Never trust frontend checks.
- No secrets in repo, prompts or client bundles. `.env.local` ignored; `.env.example` has names only.
- Privileged columns (`verification_status`, `is_suspended`, role grants) cannot be changed by end users: protected by triggers that detect the calling DB role plus `SECURITY DEFINER` RPCs.
- Audit log is append-only and written only by server-side functions.
- Rate limiting: Vercel/Upstash-style limiter on auth, OTP, upload, AI and quote endpoints **[Designed]**.
- Uploads: MIME + size allow-list at bucket level, server re-check, random object names, malware scanning job **[Designed]**.

## 5. Authentication and authorization
- Supabase Auth: email/password now; Google OAuth and phone OTP configured in the Supabase dashboard (credentials entered there, never in chat or code).
- A `profiles` row is auto-created on signup. **No role is granted automatically.**
- Roles: CUSTOMER, CONTRACTOR, SUPPLIER, ENGINEER, ARCHITECT, DRAFTSMAN, WORKER, MACHINERY_PROVIDER, COMPANY_ADMIN, PLATFORM_ADMIN. Stored in `user_roles` (a user may hold several).
- Self-service roles are granted only via `choose_role()`. `PLATFORM_ADMIN` and `COMPANY_ADMIN` cannot be self-assigned. The first admin is created manually by the project owner in the SQL editor.

## 6. RLS strategy
- RLS enabled on every table in `public`. Policies use `(select auth.uid())` so Postgres caches it per query.
- Role checks go through `is_admin()` / `has_role()` (`SECURITY DEFINER`, fixed `search_path`) to avoid recursive policies.
- Pattern: public read for reference/catalog/published data; owner read/write for own rows; admin override; **no direct write policies** on workflow tables (verification, audit, roles), which change only through RPCs.
- Every policy needs a test (anon, owner, other user, admin). **[Designed; tests are the next task once a DB is available.]**

## 7. Storage strategy
- `verification-docs`: **private**, 5 MB, JPEG/PNG/PDF. Path `{user_id}/{request_id}/{random}.ext`. Owner can upload/read own; admins read; nobody gets public URLs. Access later via short-lived signed URLs generated server-side.
- `public-media`: public, 2 MB images (avatars, logos, portfolio). Own-folder write only.
- Orphan cleanup job for files without a `verification_documents` row **[Designed]**.

## 8. API architecture
- Reads: Supabase client under RLS from server components.
- Writes with business rules: Postgres RPCs (`choose_role`, `submit_verification`, `admin_review_verification`) so web and mobile share one implementation.
- Third-party/AI/webhook endpoints: Next.js Route Handlers under `/api/v1/*`, Zod-validated, rate-limited, documented in `API.md`.

## 9. AI architecture
- Separate capabilities (assistant, cost estimator, material advisor, requirement analyzer), each with its own prompt, tool set and **structured JSON output validated by Zod** before display.
- Cost estimates follow: `user input + location + database rates + configurable assumptions + AI interpretation = estimate`. The model never invents the numbers; it calls a deterministic calculator over DB rates and explains the result.
- Every estimate shows assumptions, rate data date and a "not engineering/legal advice" notice. Conversations stored per user with retention controls. API keys server-side only.

## 10. Marketplace architecture
Discovery → comparison → communication → quotation → booking → payment → project → review. Phase 0 covers profiles and verification. Each later stage is a vertical slice with its own tables and RLS. Ranking uses documented signals (relevance, location, verification, reviews, response rate); sponsored results are always labelled and never the only factor.

## 11. Geography
`countries → regions → cities → areas`, all data rows, no hardcoded cities. Slugs unique per parent for SEO URLs. Adding UAE or UK is data entry plus a `market_config`, not a code change. Pakistan reference data seeded (provinces/territories and major cities).

## 12. Pricing architecture
- `product_prices`: one current row per (product, city, area, supplier), with `current_price`, `previous_price` (maintained by trigger), `status`, `source_type`, `updated_at`, `verified_at/by`.
- Statuses: `verified`, `supplier_submitted`, `estimated`, `historical`, `demo`. A DB check requires `verified_at` and `verified_by` for `verified`.
- `price_history` is append-only, written by trigger on every insert/price change.
- Suppliers can only write `supplier_submitted` rows for their own listing; only admins can mark `verified`.
- The `product_prices_view` exposes `display_label`, `is_fresh`, `is_demo`, `price_trend`. **The word "live" is never used**; freshness threshold is a setting (`price_stale_days`).
- Verified prices older than the threshold display as "Verified (outdated)".

## 13. Verification architecture
`unsubmitted → pending → under_review → verified | rejected` (rejection requires a note; a rejected provider may resubmit as a new request). Nothing auto-verifies. Transitions run only through `admin_review_verification()`, which validates the transition, requires ≥1 document before review, updates the profile, appends `verification_events` and `audit_logs`.

## 14. Notification architecture **[Designed]**
`notifications` table + per-user preferences; Supabase Realtime for in-app; email via provider abstraction; SMS/WhatsApp later with explicit consent and template compliance. Written by server functions only.

## 15. SEO architecture **[Designed]**
SSR/ISR pages for `/contractors/[city]`, `/materials/[category]/[city]`, `/cities/[city]`, guides. A location page is indexable only if it has real data (e.g. ≥ N published providers or ≥ N priced products); otherwise `noindex` and excluded from the sitemap. Canonicals, JSON-LD (`LocalBusiness`, `Product`/`Offer`, `BreadcrumbList`), hreflang for en/ur/ar, dynamic sitemap.

## 16. Internationalization **[Designed]**
Locale routing (`/en`, `/ur`, `/ar`), `dir` set from locale, logical CSS properties for RTL, ICU message files (no strings in components), `Intl` for dates/numbers/currency, per-country unit and currency configuration. Database content translations via `name_i18n` jsonb now, a `translations` table if volume demands.

## 17. Payment and monetization **[Designed, not active]**
Payments sit behind a provider-agnostic interface (`PaymentProvider`) with lifecycle `created → pending → processing → succeeded | failed | refunded | cancelled`, confirmed server-side by webhook only. Pakistan providers and their current terms must be verified before integration. Subscriptions, featured listings, paid leads and commissions are config-driven from admin. No money flows until the marketplace loop and legal review are done.

## 18. Risks and mitigations
| Risk | Mitigation |
|---|---|
| Empty marketplace (no supply) | Seed supply via manual onboarding; free tier; demo data clearly labelled |
| Fake/stale prices destroy trust | Status model, freshness view, verified-only badge, admin verification |
| Privilege escalation via RLS gaps | Protected-column triggers, RPC-only workflows, RLS tests in CI |
| Identity document leakage | Private bucket, signed URLs, admin-only read, audit logs |
| Spam/abuse in leads and reviews | Rate limits, verified-purchase reviews, moderation queue |
| AI hallucinated estimates | Deterministic calculator, schema validation, visible assumptions |
| Vendor lock-in | Plain SQL migrations, portable code, documented export |
| Local legal/regulatory (data, payments) | Flag for qualified legal advice before launch |
| Over-engineering | Vertical slices; deferred tables listed above |

## 19. Roadmap
1. **Phase 1 (now):** foundation schema, auth, roles, onboarding, profiles, verification, admin review.
2. **MVP:** materials + city/area price comparison → contractor marketplace → search → quotes/leads → AI assistant → cost calculator → projects → reviews → notifications → admin → SEO → hardening → deploy.
3. **After validation:** supplier dashboards, messaging, subscriptions/payments, machinery rental.
4. **Scale:** Gulf expansion via data, search engine (e.g. Postgres FTS → dedicated), mobile apps on the same API.
