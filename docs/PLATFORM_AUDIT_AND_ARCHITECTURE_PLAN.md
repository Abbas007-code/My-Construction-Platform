# My Construction Platform: Audit, Architecture and Phased Plan

Status: PLAN ONLY (v0.1, 2026-10-11). Produced by a read-only audit. No migration was applied, nothing was deployed, no commit was made, and no application code was written.

Companion documents: `CALCULATION_ENGINE_SPEC.md`, `PRODUCT_CATALOG_AND_COMMERCE_SPEC.md`, `DELIVERY_AND_PAYMENT_SPEC.md`, `PROFESSIONAL_SERVICES_SPEC.md`, `ACCEPTANCE_TEST_MATRIX.md`, `DECISION_REGISTER.md`, `../ARCHITECTURE.md`.

## 1. Audit: what actually exists (verified 2026-10-11)

### 1.1 GitHub
| Item | Finding | Basis |
|---|---|---|
| Repository | `Abbas007-code/My-Construction-Platform`, private, default branch `main` | Connector query |
| Remote content | Empty: no branches, no commits, no files | Connector query (409 "repository is empty") |
| Connector | Connected, enabled in chat | Connector listing |
| Session git access | The session's repository list shows the repository with push permission; it is not yet attached to this session, so `git push` is untested | Repository listing and a refused command-line call |
| Command-line auth | `GH_TOKEN` and `GITHUB_TOKEN` set and `GH_TOKEN` invalid; no stored login | `gh auth status` (values never printed) |
| Unrelated repository | `Abbas007-code/ponytail` (public fork) is visible to the session; untouched | Repository listing |

### 1.2 Local project folder
Git repository initialised on `main`, `origin` set to the repository above, 14 files staged, no commits. Contents: six migration files (`0001` to `0006`), `seed.sql`, `ARCHITECTURE.md`, `.gitignore`, four specification documents, `DECISION_REGISTER.md`. Secret scan of the staged content: no matches (control-checked). No application code exists: no `package.json`, workspace file, TypeScript config, Next.js or mobile project.

### 1.3 Supabase (project `trjrkzkpdilgyfuogfba`, Mumbai)
| Item | Finding |
|---|---|
| Migration history | 5 applied: foundation, security_private_helpers_and_publish_rules, audit_coverage_and_helper_hardening, fix_admin_set_suspension_user_not_found, materials_pricing |
| Repo vs remote | Normalised hashes of `0001` to `0005` matched the remote history when last compared (2026-10-10); today's audit re-confirmed the same five migration versions and names but did not recompute hashes |
| Not applied | `0006_storage.sql`, `seed.sql` (storage buckets: 0; all data tables: 0 rows; 0 auth users) |
| Security objects | 36 RLS policies, 19 triggers, 16 public functions; every public table has RLS enabled |
| Extensions installed | `plpgsql`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `supabase_vault` only. Available but not installed: `postgis`, `pg_trgm`, `vector`, `pg_jsonschema`, `pgtap`, `pg_cron`, `pgmq`, `pg_partman` |
| Edge functions | None deployed |
| Advisors (2026-10-10) | Security: 4 WARN (the four intended RPCs). Performance: 10 unindexed foreign keys (INFO), 6 unused indexes (INFO, empty database), 13 `multiple_permissive_policies` (WARN) |

### 1.4 What has been implemented and tested
| Area | Implemented in database | Tested (executed) |
|---|---|---|
| Geography schema | Yes (tables, composite FKs) | Structure only; no data |
| Roles, profiles, provider profiles | Yes | Earlier suites: 64 PASS, then 189 PASS / 0 FAIL after 0003/0004 (recorded in earlier sessions; not re-run in this task) |
| Verification workflow, publishing rules, suspension, audit triggers | Yes | Same earlier suites |
| Catalog (categories, brands, products), price engine, price history, public price view | Yes (0005) | 84 PASS / 0 FAIL, rolled back (2026-10-09) |
| Storage buckets and policies | Written (0006), not applied | None |
| Seed data | Written, not applied | None |
| Quotes, orders, delivery, payments, reviews, projects, messages | Not built | None |
| Web or mobile application | Not built | None |
| Calculation engine, AI assistant | Not built | None |

Test counts above are historical results from earlier sessions. Today's audit executed read-only queries only (migration list, row counts, RLS and object counts, extension and edge-function lists, repository state).

## 2. Risks and dependencies found

| # | Risk or dependency | Severity | Note |
|---|---|---|---|
| R1 | Source is not in version control; the only copy of migrations and specs is this working folder and the live database | High | Needs the baseline push; blocked on session attachment of the repository |
| R2 | Command-line GitHub token invalid | Medium | Environment secret settings; no token to be pasted in chat |
| R3 | Past parallel application of a migration (0002) by another session | Medium | Decision D-23: one applier at a time |
| R4 | Price model allows one price per product, city, area, supplier, and one unit per product | High for catalog growth | D-17; blocks tiles, packs, bulk bands |
| R5 | No unit registry or conversions | High for the calculation engine | Must exist before any quantity feature |
| R6 | Category attributes are free-form jsonb | Medium | D-18 |
| R7 | Several performance advisories unresolved | Low now, rising with data | Review before real traffic |
| R8 | Single admin role | Medium | D-6, before finance features |
| R9 | No automated test harness in the repository; tests were run through a SQL tool in rolled-back transactions | High | Needs pgTAP or scripted tests in CI |
| R10 | No concurrency test capability | Medium | D-20 |
| R11 | Forged verification stamps are silently discarded | Low | D-3 |
| R12 | Legal and regulatory unknowns (payments, consumer protection, data protection, professional liability for estimates) | High | Qualified legal advice needed before launch |
| R13 | All local-market data (prices, specs, densities, wastage norms, delivery rules) absent | High | Cannot be invented; needs sourced data |

## 3. Recommended cross-platform architecture

### 3.1 Principles
1. One database and one policy layer (Supabase Postgres with RLS) serves every client. Business rules that protect money, identity and visibility live in the database.
2. One language across clients (TypeScript) so web and mobile share domain code.
3. One deterministic calculation engine (pure TypeScript), shared and versioned, never inside the language model.
4. Responsive web first, mobile second, on the same shared packages.
5. Country, currency, language and unit behaviour is data and configuration, not code branches.

### 3.2 Proposed repository layout (not created)
```
apps/
  web/            Next.js (App Router, TypeScript): responsive for desktop, tablet, phone; SSR/ISR for SEO pages; installable PWA
  mobile/         Expo (React Native, TypeScript): Android and iOS; added after the web journey works
packages/
  domain/         shared types, Zod schemas, enums, role and status state machines (no UI, no I/O)
  calc-engine/    pure deterministic calculation functions (see CALCULATION_ENGINE_SPEC.md)
  units/          unit registry types and conversion functions (exact decimal arithmetic)
  api-client/     typed Supabase client wrappers, generated database types, query helpers
  i18n/           message catalogs (English, Urdu, Arabic), formatting helpers, RTL utilities
  ui-tokens/      colours, spacing, typography as data (shared); components remain separate per platform
supabase/
  migrations/     forward-only SQL (already exists)
  tests/          pgTAP or SQL test suites for RLS and functions
  functions/      server-side functions for AI, webhooks, scheduled jobs (only when needed)
docs/
```
Monorepo tooling: pnpm workspaces with Turborepo (task caching), GitHub Actions for lint, type check, unit tests, database tests and secret scanning.

### 3.3 Why this stack
- **Next.js plus Expo, both TypeScript:** maximum code sharing for domain logic, validation, calculation and API access without forcing one UI toolkit across web and native. Both are widely used and maintained.
- **Not Flutter or FlutterFlow:** FlutterFlow was abandoned; Flutter would split the language and prevent sharing the calculation engine and validation with the web app.
- **Alternative considered:** a single cross-platform UI framework for everything. It reduces UI duplication but weakens SEO and web-native behaviour, which are core acquisition requirements. Not recommended now.
- **Lock-in control:** plain SQL migrations, standard Postgres, portable TypeScript packages; Supabase specifics confined to `api-client`.

### 3.4 What is shared between web and mobile
| Shared | Not shared |
|---|---|
| `domain` types and Zod schemas | Screens and navigation |
| `calc-engine`, `units` | Platform UI components |
| `api-client` and generated database types | Push notification and camera or file-picker integrations |
| `i18n` catalogs and formatters | Web-only SEO pages, sitemap, metadata |
| State machines (quote, order, delivery) as pure functions | Native build and store release pipelines |
| Design tokens | |

### 3.5 Security architecture (carried forward)
Browser and mobile apps hold only the publishable key. The service-role key lives only in server-side environment settings. Server routes validate input, check authorisation, and rely on RLS as the final authority. Private files use signed URLs generated server-side. Secrets never enter the repository (`.gitignore` prepared; CI secret scanning to be added).

### 3.6 Localisation and regions
English, Urdu and Arabic through message catalogs with locale routing and `dir` from locale; logical CSS properties on web and I18nManager on native for right-to-left. Currency, unit system, tax display, payment methods and number or date formats come from per-country configuration rows. Pakistan is the first configured market, not a code assumption.

## 4. Regional prices, specifications, units, delivery and currency: representation

Detailed fields live in the catalog and delivery specifications; this summarises the representation.

| Concern | Representation |
|---|---|
| Regional prices | Versioned price records (supplier, variant, location, unit, currency, status, source, effective and review dates, history). Existing `product_prices` covers a subset; extension tracked as D-17. Every number carries its status (verified, supplier submitted, estimated, historical, demo) |
| Material specifications | Category-level attribute definitions (key, type, unit dimension, allowed values, required) and validated attribute values on variants. Supplier-stated values stay as supplied |
| Unit conversions | Units registry plus conversion rules with scope (global exact, category, material-specific) and source. Volume-to-mass and vehicle-load conversions only where a documented density or supplier-confirmed rule exists. Original supplier unit always preserved |
| Delivery costs | Delivery zones, vehicle types (capacities only if sourced), fee rules (base, distance, weight or volume, loading, unloading, waiting, remote surcharge) or a supplier quotation. If neither is reliable the answer is "quotation required" |
| Local currencies | ISO 4217 code on every amount; `numeric` storage; the country's default currency enforced on prices today. Exchange rates, if ever used, are display-only, dated, sourced, and never silently convert a verified local price |
| Languages | `name_i18n` style columns and message catalogs; no display text in code |

## 5. Calculation engine and AI (summary)
The engine is a separate, deterministic, versioned package; the language model never produces quantities or prices. Full design: `CALCULATION_ENGINE_SPEC.md`. The assistant extracts structured inputs from conversation, asks for missing ones, calls the engine, and explains the output. It labels every result as an estimate, shows assumptions, and refuses to present structural, electrical, fire-safety or legal design as certified work.

## 6. Phased implementation plan

Each phase ends with a report containing: files changed, database changes, tests executed, tests passed and failed, security and performance findings, remaining risks, and the next recommended step. No phase is called complete until its acceptance tests have actually run and passed. Any migration needs your approval and a reviewed file first. Dependencies on decisions are listed.

### Phase 0: Source-control baseline (current blocker)
- **Work:** attach the repository to the session, commit the 14 staged files, push, verify the remote.
- **Database changes:** none.
- **Acceptance tests:** remote commit hash equals local; 14 tracked files; repeat secret scan clean; working tree clean; five migrations still match remote history.
- **Depends on:** repository attachment; D-22; D-23.

### Phase 1: Workspace, CI and database test harness
- **Work:** monorepo scaffold (pnpm, Turborepo, TypeScript strict, lint), CI pipeline, secret scanning, pgTAP or scripted RLS tests that re-run the 84 and earlier suites against a disposable database.
- **Database changes:** none to production. Test database is disposable.
- **Acceptance tests:** CI runs lint, type check and unit tests green; the ported 0005 suite reproduces 84 PASS / 0 FAIL on a disposable database; a deliberately broken policy makes a test fail (negative control).
- **Depends on:** Phase 0; D-20.

### Phase 2: Authentication and role-aware web shell
- **Work:** `apps/web` with sign-up, sign-in, role onboarding (`choose_role`), role-aware routing, error and permission-denied states, English with message catalogs in place.
- **Database changes:** none expected (existing roles and RPCs). Storage 0006 is optional here.
- **Acceptance tests:** end-to-end sign-up and role selection against a test project; unauthorised route access is denied; the four RPCs refuse anonymous and wrong-role callers (re-run targeted tests); no service-role key in the client bundle (bundle scan).
- **Depends on:** Phase 1; Supabase test project or branch (not production).

### Phase 3: Catalog read path with real queries
- **Work:** home, categories, product list and details, price display with status labels, supplier details (verified providers only).
- **Database changes:** seed of foundational data only if approved (`seed.sql` review), no demo prices unless labelled.
- **Acceptance tests:** anonymous users see only visible prices (re-run matrix A to H through the app); labels match status; empty, loading and error states present; performance check on list and details queries with realistic synthetic volume.
- **Depends on:** D-1, D-2, seed approval.

### Phase 4: Units, attributes and price-model foundation
- **Work:** units registry, conversion rules, attribute definitions (two or three categories first), price-model extension.
- **Database changes:** new migrations (reviewed first). Applied one at a time, with hash verification after each.
- **Acceptance tests:** conversion fixtures exact (including round trips); invalid attributes rejected; existing 84-case suite still 0 FAIL; new RLS tests for every new table.
- **Depends on:** D-8, D-17, D-18.

### Phase 5: Calculation engine v0 (no AI)
- **Work:** `calc-engine` with a small set of work items, assumption registry, versioned output records.
- **Database changes:** tables for assumptions and calculation records (reviewed migration).
- **Acceptance tests:** golden-vector unit tests with exact decimals; missing assumption returns "needs assumption", never a guess; every output line cites formula and assumption ids; rounding rules verified; engine version stored.
- **Depends on:** Phase 4; sourced assumption values from you or qualified professionals.

### Phase 6: Quote requests and supplier quotations (goods)
- **Work:** request quote, supplier inbox, quotation submission, comparison, acceptance semantics.
- **Database changes:** quote tables and state machine (reviewed migration).
- **Acceptance tests:** state transitions by permitted actors only; customer B cannot read customer A's requests; duplicate submission prevented; totals computed server-side equal line sums.
- **Depends on:** Phases 3 and 4; D-4, D-5.

### Phase 7: AI construction assistant (assistive, not authoritative)
- **Work:** natural-language intake, structured-input extraction with user confirmation, engine call, explanation and labelling; no numbers from the model.
- **Database changes:** conversation and audit tables if retained (reviewed).
- **Acceptance tests:** adversarial prompts cannot make the assistant state an unapproved structural design as certified; every number in a reply matches engine output (automated check); estimate labels and assumptions always present; prompt-injection test set; refusal behaviour for structural, electrical, fire-safety and legal requests.
- **Depends on:** Phase 5.

### Phase 8: Mobile app
- **Work:** Expo app reusing shared packages; same journeys as web.
- **Acceptance tests:** shared-package tests pass unchanged on both; device checks on at least one Android and one iOS version; right-to-left layout check; offline and slow-network behaviour for read paths.
- **Depends on:** Phases 2 to 6.

### Phase 9: Orders, delivery and payments
- **Work:** orders, delivery records, cash policy first, online provider only after verification.
- **Database changes:** substantial; staged migrations, each reviewed.
- **Acceptance tests:** per the acceptance matrix areas 6 to 9, 13 to 15, 18.
- **Depends on:** D-5, D-9 to D-12; legal review.

### Phase 10: Services marketplace, reviews, projects, messaging
Per `PROFESSIONAL_SERVICES_SPEC.md`; depends on D-13 to D-16.

### Phase 11: International expansion
Second country as configuration and data only; no code branches for country; localisation review for Urdu and Arabic quality.

## 7. Immediate next steps (all need your input)
1. Attach the repository to the session and approve the baseline commit and push (Phase 0).
2. Replace the invalid command-line tokens in the environment's secret settings.
3. Review D-22, D-23 and D-17.
4. Confirm the proposed stack (Next.js plus Expo, pnpm and Turborepo) before any scaffold is created.

## 8. Report for this audit phase
- **Files changed:** this document and `CALCULATION_ENGINE_SPEC.md` added under `docs/`. Nothing else changed since the 14 files were staged. The two new files are untracked.
- **Database changes:** none.
- **Tests actually executed:** read-only audit queries only (listed in Section 1). No behavioural test suite was run in this phase.
- **Passed / failed:** not applicable for behavioural tests; audit checks returned the same five migrations, zero data rows and RLS enabled on every public table.
- **Security and performance findings:** unchanged from the 2026-10-10 advisor results; risks R1 to R13 above.
- **Remaining risks:** see Section 2.
- **Next recommended step:** Phase 0.
