# My Construction Platform: Construction Calculation Engine Specification

Status: DESIGN ONLY (v0.1, 2026-10-11). Nothing in this document is implemented. No migration is proposed for application yet. The only numbers in this document are (a) exact unit definitions and (b) clearly labelled ILLUSTRATIVE test inputs whose arithmetic was checked; none are market data, norms or recommendations.

## 1. Purpose and non-negotiable rules

The engine turns validated project inputs, documented assumptions and sourced regional data into a bill of quantities and a cost estimate. It is a separate, deterministic program. The language model never calculates, never supplies a quantity, a rate or a norm, and never overrides the engine.

1. **No invented numbers.** Every quantity comes from an explicit formula applied to validated inputs. Every wastage allowance, mix ratio, coverage rate or density comes from the assumption registry with a source and an approval record. If a required assumption is missing, the engine returns `NEEDS_ASSUMPTION` naming it. It never substitutes a default.
2. **No invented prices.** Every cost line references a stored price record (with its status and source). With no applicable price the line shows quantity only and `PRICE_UNAVAILABLE`. Demo, historical and estimated prices keep their labels; nothing is called current or verified unless the record says so.
3. **Deterministic and reproducible.** Same inputs, same assumption set, same price snapshot, same engine version produce the same output. Outputs store all four references.
4. **Exact arithmetic.** Decimal arithmetic only (no binary floating point). Rounding happens at defined points with stated rules. Demonstration: binary floating point gives 0.1 + 0.2 = 0.30000000000000004, decimal gives 0.3.
5. **Estimates, not engineering.** Output is a preliminary quantity and cost estimate. It is not structural, architectural, electrical, plumbing, fire-safety, geotechnical or legal design, and not a certified bill of quantities. Every output carries that statement and the professional-review flags in Section 8.
6. **Scope boundary.** The engine performs quantity take-off from dimensions the user supplies. It does not size structural members, design reinforcement, select concrete mix designs, or interpret building codes. Where a quantity depends on those (for example reinforcement weight, cement per cubic metre), it requires either professional-supplied quantities or an approved assumption set clearly labelled preliminary.

## 2. Architecture

```
user or AI assistant
        |  structured input (validated, user-confirmed)
        v
 input validation (schema, ranges, units)
        |
        v
 calc-engine (pure TypeScript package, versioned)
   reads:  assumption set (versioned, approved)
           unit registry and conversion rules
           price snapshot (regional, status-labelled)
   writes: calculation record (inputs, assumption ids, price ids,
           engine version, outputs, warnings)
        |
        v
 results to UI and to the AI assistant (explanation only)
```

- **Package:** `packages/calc-engine` (pure functions, no network, no clock, no randomness) plus `packages/units`. Shared by web, mobile and server.
- **Authoritative run:** server-side. Clients may run the same package for instant previews, but the saved calculation is the server's run, and any quote or order built from it re-runs it.
- **Formulas live in reviewed code, parameters live in data.** Formula modules are code reviewed and tested like any other. Wastage factors, mix ratios, coverage rates, densities and similar parameters are rows in versioned tables. The engine does not execute formula text from the database.
- **Versioning:** semantic engine versions; every formula module has an id and version; changing a formula creates a new version, never edits an old one. Old calculation records remain reproducible against their recorded versions.

## 3. Input model

Inputs are a typed, validated structure (Zod schema in `packages/domain`), organised as:
- **Project context:** country, region, city, area, currency, unit system, project type, number of floors, quality or finishing tier (as defined by the market configuration).
- **Geometry:** dimensions with explicit units (length, width, height, thickness, openings), counts, plot area and covered area as separate fields.
- **Work items:** a list of selected items (for example floor tiling, slab concrete volume, wall plaster area, painting area), each with its own parameters.
- **Material choices:** references to catalog variants (not free text) where a quantity must map to a purchasable pack.
- **Assumption set reference:** which approved assumption set applies.

Validation rules: every numeric field has a unit, a minimum and a maximum; units are converted to base units through the registry before calculation; contradictory inputs (for example covered area larger than plot area where the market configuration forbids it) are reported, not silently fixed. The AI assistant may help the user fill these in, but the user confirms the final structured input before any calculation runs.

## 4. Assumption registry

Each assumption is a row with: key, value, unit, applicable scope (country, region, project type, work item), source reference (document, supplier statement, professional sign-off), approver, valid-from and valid-to, status (draft, approved, retired), and notes. Rules:
- Only `approved` rows within their validity window are usable.
- Each output line lists the assumption ids it used.
- Changing a value creates a new version; old versions stay for reproducibility.
- Values are never seeded by the platform without a source. Examples of parameters that need sourced values (no values are proposed here): wastage allowances by material and work item, coverage rates for paints and finishes, mix proportions, brick and block dimensions and mortar allowances, densities for volume-to-mass conversion, labour productivity if labour is estimated.

## 5. Units and conversion

- **Registry:** `units` (code, dimension, symbol, localised names) and `unit_conversions` (from, to, factor or function, scope, source, approver).
- **Exact definitions that may be built in as global rules** (international definitions): 1 inch = 25.4 mm exactly; 1 foot = 0.3048 m exactly; therefore 1 square foot = 0.09290304 m² exactly; 1 pound = 0.45359237 kg exactly. Executed check: 0.3048² = 0.09290304; round trip 10 ft to m and back returns 10.
- **Scoped rules:** volume-to-mass (density), packaging (pieces per box or bag), and vehicle-load conversions are never global. They exist only as category or material rules with a source. Conversions without a rule return `CANNOT_CONVERT`.
- **Regional commercial units** (for example per hundred, per thousand, local land-area units) are data rows with a stated base and source; they must be confirmed before use (decision D-8).
- **Original unit preserved:** supplier-stated units and quantities stay alongside any converted figure.
- **Rounding:** each dimension has a stated precision for display and for purchase rounding (round up to whole packs where a pack is indivisible). Intermediate values keep full decimal precision.

## 6. Formula modules

A formula module is a pure function with: id, version, input schema, required assumption keys, output schema, and documented derivation. The first set to build (design intent, none implemented) uses only geometry, counts and approved parameters:

| Module | Derivation (symbolic) | Needs approved assumption |
|---|---|---|
| Rectangular area | area = length x width | none |
| Floor or wall tiling | net tiles = surface area / area per tile; gross tiles = net tiles x (1 + wastage); tiles to buy = round up; packs = round up (tiles to buy / tiles per pack) | wastage allowance (source required) |
| Slab or footing volume | volume = length x width x thickness | allowance if any (source required) |
| Wall surface area | area = perimeter x height minus openings | none |
| Painting area and quantity | quantity = surface area x number of coats / coverage per unit | coverage per unit (supplier-stated, sourced), coats count |
| Brick or block count | count = wall area / area per unit (including joint rule) | unit dimensions and joint allowance (sourced) |
| Concrete constituents (cement, sand, aggregate) | requires an approved mix assumption set | mix proportions (sourced; labelled preliminary) |
| Reinforcement | not computed from rules of thumb; requires professional-supplied schedule | not offered without a schedule |

Modules that depend on structural design inputs (reinforcement, member sizing) are intentionally not computed by the engine from shortcuts. If an approved preliminary assumption set exists, the output is labelled preliminary and flagged for engineer review.

### 6.1 Illustrative test vectors (executed; NOT data)
All inputs below are made up solely to test mechanics. Values such as wastage 10 percent and rate 1000.00 are placeholders, not norms or prices.

| Case | Inputs (illustrative) | Expected output | Executed result |
|---|---|---|---|
| Floor tiling | room 4.0 m x 3.5 m; tile 600 mm x 600 mm; 4 tiles per box; wastage 0.10; rate 1000.00 per box | area 14.00 m²; area per tile 0.36 m²; net tiles 38.8889; gross 42.7778; tiles to buy 43; boxes 11 (44 tiles); cost 11000.00 | Matches (decimal arithmetic) |
| Area conversion | 14 m² to square feet | 150.6947 ft² (4 decimal places) | Matches |
| Slab volume | 5.0 m x 4.0 m x 0.15 m; allowance 0.05 | 3.0000 m³; with allowance 3.150000 m³ | Matches |
| Missing assumption | tiling requested with no approved wastage | `NEEDS_ASSUMPTION: wastage` | To be tested when built |
| No price | tiling with no price record | quantities returned; cost line `PRICE_UNAVAILABLE` | To be tested when built |

These vectors become the first golden tests when the engine is built.

## 7. Prices, delivery and regional adjustments in the engine

- **Price lookup:** by variant, pack, unit, location (area, city, region, country), supplier (optional), effective date. Several suppliers produce a range, not a single blended number. The output shows each price's status and age; unverified or outdated prices are labelled.
- **Quantity pricing:** only stored tier rules, never invented discounts.
- **Delivery:** only from stored fee rules or a supplier quotation. If neither exists the delivery line is `QUOTATION_REQUIRED`.
- **Tax:** per country configuration, shown separately; rates need sourced data (decision D-7).
- **Currency:** each line carries its currency; all lines of one estimate use the project's currency. If prices are in another currency, the engine reports that mismatch; it does not convert silently. Any conversion would use a dated, sourced rate shown to the user.
- **Ranges and confidence:** where prices vary across suppliers or dates, show minimum, maximum and the contributing records. Do not present a mean as the market price.

## 8. Output model and labelling

Each calculation record contains: id, engine version, formula module versions, input snapshot, assumption ids, price record ids, unit conversions used, output lines, warnings, and timestamps. Each line: item, quantity, unit, purchase unit and packs, formula id, assumption ids, price reference and status, subtotal, flags.

Mandatory labels on every output (shown in the UI and quoted by the assistant):
- "Preliminary estimate based on the inputs and assumptions listed. Not an engineering design, not a certified bill of quantities, and not a quotation."
- Price status per line (Verified, Supplier submitted, Estimated, Historical, Demo) and price date.
- Professional-review flags where relevant: structural elements, electrical and gas work, fire safety, legal and permit matters, soil and foundation conditions.
- Missing inputs and missing assumptions listed, never hidden.

## 9. AI assistant boundary

| The assistant may | The assistant must not |
|---|---|
| Ask questions to complete structured inputs | Compute or estimate quantities or costs itself |
| Show the user the structured input for confirmation | Choose assumption values (wastage, mix, coverage) on its own |
| Call the engine and display its output | Round, adjust or "sanity-fix" engine numbers |
| Explain formulas, assumptions and labels in plain language | Present results as certified, approved or guaranteed |
| Suggest which qualified professionals to consult | Provide structural, electrical, fire-safety or legal design as certified work |
| Say "I cannot estimate that" when inputs or assumptions are missing | Invent prices, brands, densities or local norms |

Enforcement (to be built and tested, not yet existing):
1. Tool-based design: the model only has tools that call the engine and read catalog data; there is no free-form numeric output path.
2. Response checking: an automated check extracts every number in a reply and verifies it appears in the engine output or the user's input; failures block the reply.
3. Fixed disclosure block appended by the application, not by the model.
4. Refusal rules and tests for structural, electrical, fire-safety and legal requests, and for attempts to override labels.
5. Prompt-injection tests, including injection via supplier text and uploaded documents.
6. Logged inputs, tool calls and outputs (with privacy controls) for audit.

## 10. Data model sketch (proposed, not created)

| Table | Purpose |
|---|---|
| `units`, `unit_conversions` | Registry and scoped conversion rules |
| `calc_assumption_sets`, `calc_assumptions` | Versioned approved parameters with sources |
| `calc_formula_modules` | Registered module ids and versions (metadata, not executable text) |
| `calc_runs`, `calc_run_lines` | Saved calculation records, reproducible |
| `calc_reviews` | Professional review notes and approvals attached to a run |

All tables need RLS: users see their own runs; assumption tables are readable according to approval status; writes restricted to authorised roles, audited. No migration is applied until you approve a reviewed file (decision D-17 and the unit decisions come first).

## 11. Professional review workflow
A run can be sent to a qualified professional on the platform (engineer, architect, quantity surveyor). Their review is attached as a separate record naming the reviewer, scope and date, and never edits the original run. Only a professional-approved run may be described as "professionally reviewed", and only within the scope the reviewer stated. Verification of professional status uses the existing verification workflow. Licensing norms differ by country (DATA; qualified legal advice recommended).

## 12. Acceptance tests (to run when built)

| ID | Test | Expected |
|---|---|---|
| CE-1 | Golden vectors (Section 6.1) in decimal arithmetic | Exact expected values |
| CE-2 | Round-trip and exact-definition conversion tests | Exact |
| CE-3 | Conversion with no rule | `CANNOT_CONVERT` |
| CE-4 | Missing assumption | `NEEDS_ASSUMPTION`, no default used |
| CE-5 | Missing price | Quantity only, `PRICE_UNAVAILABLE` |
| CE-6 | Retired or out-of-window assumption | Rejected |
| CE-7 | Same inputs and versions run twice | Identical output |
| CE-8 | Output lines cite formula and assumption ids | Always present |
| CE-9 | Mixed-currency prices | Mismatch reported, no silent conversion |
| CE-10 | Purchase rounding (indivisible packs) | Rounded up as specified |
| CE-11 | Input validation (negative, absurd magnitude, wrong unit, contradictory fields) | Rejected with clear message |
| CE-12 | Rows-level security on calc tables (own runs only; other users denied) | Denied |
| CE-13 | AI reply number check (every number traceable) | Untraceable number blocks reply |
| CE-14 | AI refusal tests (structural, electrical, fire, legal; override attempts) | Refuses, adds referral to qualified professional |
| CE-15 | Prompt-injection suite | No policy bypass |
| CE-16 | Required labels present on every output | Always present |
| CE-17 | Engine version change keeps old runs reproducible | Old run recomputes identically with recorded versions |

## 13. Decisions and data needed
- D-8 (first commercial units), D-17 (price model), D-18 (attribute validation), D-7 (tax display).
- New: **D-25** which work items first (recommended: tiling, slab volume, wall area, paint quantity); **D-26** who approves assumption values and under what qualification; **D-27** whether professional review is offered inside the platform at launch and on what terms (liability and licensing; qualified legal advice recommended); **D-28** where the authoritative run executes (recommended: server-side function in the application backend, same package as the client).
- Data: sourced wastage, coverage, dimension and density values for the launch market; none are supplied by this document.
