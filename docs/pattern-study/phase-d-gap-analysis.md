# Phase D — Dual Gap Analysis

**2026-08-10 · Every gap anchored to a verified measurement.** Sources: Phases A–C (`phase-a-pdw-inventory.md`, `phase-b-sdw-inventory.md`, `phase-c-benchmark.md`). Gap candidates = rubric dimensions scoring ≤2. Format: what's missing → what it costs today → what closing it takes.

---

## Part 1 — SDW gaps

### SDW-G1 · No assertion layer (rubric #6, score 2) — SEVERITY: HIGH
- **Missing:** dbt schema tests (zero exist), CI-gating invariants, cross-surface tie-outs. All verification is nightly and non-blocking.
- **Costs today:** A bad PR merges green and runs against prod that night; the DL-15 duplicate class was *detected* by check 8 only after rows had already inflated (WARN state lived in reconciliation.json for weeks). Cross-surface: BI convergence is manual report-by-report; nothing would catch app-vs-Metabase disagreement.
- **To close:** (a) generated `unique`/`not_null`/`accepted_values` tests on all dims + incremental facts (~1 day, mostly mechanical); (b) a golden-style invariant suite — active-customer identity, fact-grain uniqueness, company-registry coverage — run in CI against staging mirror and nightly against prod; (c) tie-out check between `public_semantic` and `public_bi_compat` on shared metrics. PDW reference: golden suite + `check_cohort_ties`.

### SDW-G2 · No conformed identity (rubric #3, score 1) — SEVERITY: HIGH, RISING
- **Missing:** Any customer identity above (source_id, _company_name). No crosswalk, no merge ledger, no exclusion registry.
- **Costs today:** Cannot answer any Skimmer↔QBO question (blocking for BI Invoice convergence, DL-16); 101 source-side merges left zero trace (proved 2026-08-09); no governed way to exclude test/internal records — they silently count in every metric.
- **To close:** Not a full MDM build. Start: (a) `core_identity` schema with `customer_alias` (old→survivor, reason, decided_by) and `member_exclusion` (single choke point, PDW pattern); (b) staging models honor both; (c) crosswalk to QBO deferred until a QBO source actually lands — but the *slot* exists from day one. PDW reference: registry_member/master_id_alias/member_exclusions; their crosswalk_guard shows deterministic-only automation works.

### SDW-G3 · No history where sources forget (rubric #4, score 1) — SEVERITY: HIGH, COMPOUNDING DAILY
- **Missing:** SCD on dims; any retention of rows that age out of the 6-month window; tombstones for upstream deletions.
- **Costs today:** Cancellation date inferred from `updated_at` (fragile workaround, already caused the non-functional freshness guard's cousin bugs); every restatement question ("what did this look like last month?") unanswerable; history destroyed silently every night and **cannot be backfilled later** — this is the only gap where waiting has irreversible cost.
- **To close:** (a) dbt snapshots on dim_customer, dim_service_location (rate!), stg_route_assignment — days, not weeks; (b) append `_loaded_at`/`_extract_date` to facts (= existing ETL-6); (c) customer-identity ledger that outlives the window (joins SDW-G2). PDW reference: episode logic, frozen rosters, *_log siblings.

### SDW-G4 · No monitoring completeness (rubric #8, score 1) — SEVERITY: MEDIUM, CHEAP, GATES NEW SOURCES
- **Missing:** Feed registry; unmonitored-feed detection; schedule-aware freshness evaluation.
- **Costs today:** The open freshness-guard false-WARN question (manual early-hours runs) is exactly a missing schedule calendar; a new source (Samsara/Xima/QBO) could ship with no freshness expectation and fail silently forever.
- **To close:** `etl.feed_registry` table (source, company, max_age_hours, active_hours, note) + one check consuming it + unregistered-feed detection (compare against etl_load_log distinct sources). ~40 lines against existing harness. **Sequencing rule: land before any new source onboarding.** PDW reference: feed_registry + schedule-aware guard — direct lift.

### SDW-G5 · Semantics ungoverned as data (rubric #5, score 2) — SEVERITY: MEDIUM
- **Missing:** Versioning, ownership, approval provenance, and SQL-joinability for business definitions; governed tag vocabulary.
- **Costs today:** 495 active customers ambiguous-multi-cohort (CLERMONT 362/475 — cohort analysis unusable); "active customer" definition exists in 3 prose places with no version discipline; no way for a dbt model to *join* a definition.
- **To close:** (a) `defined_terms` as dbt seed (term, version, definition, rule_ref, approved_by) — populate from existing YAML + glossary, get Ross sign-off as the charter event; (b) `tag_catalog` seed with owner + category + active flag; (c) entity_registry seed (24 rows, from PDW backup analysis) for cohort hierarchy. PDW reference: defined_terms + charter process + tag_catalog.

### SDW-G6 · Ingestion robustness gaps (rubric #11, score 2) — SEVERITY: MEDIUM
- **Missing:** Per-company failure isolation; wall-clock watchdog; upstream-outage retry classes.
- **Costs today:** One company's extract failure can fail the whole nightly run (all three process in one pipeline invocation); no defense against a hung read of a corrupt/slow OneDrive file.
- **To close:** (a) per-company try/isolate in etl/main.py with per-company status rows (PDW matrix pattern, translated); (b) wall-clock budget on extract reads. Modest effort; triage.py already gives us the alerting half PDW lacks.

### SDW-G7 · Provenance below target (rubric #12, score 2) — SEVERITY: LOW-MEDIUM (already backlogged)
- **Missing:** Row-level provenance (ETL-6), trace CLI (ETL-7), point-in-time recon snapshots (ETL-8), full schema governance (ETL-9).
- **Costs today:** "When did this row enter?" unanswerable; drift detection is fingerprint-seed only.
- **To close:** Existing backlog items are correctly scoped — this gap analysis mostly *re-prioritizes* them (ETL-6 rises: it's also the history story's fact half).

### SDW-G8 · Serving-layer honesty (rubric #13, score 1) — SEVERITY: LOW, TRIVIAL FIX, HIGH TRUST ROI
- **Missing:** Any user-visible data-currency indication.
- **Costs today:** Users cannot distinguish "fresh as of this morning" from "pipeline broke 3 days ago" — trust erodes invisibly; support questions land on Ross.
- **To close:** `/api/freshness` endpoint reading etl_load_log + report freshness logic (exists) + header badge in React. Hours. PDW reference: warehouse_asof.

---

## Part 2 — PDW gaps (advisory — Sam's to accept or decline)

### PDW-G1 · No change management (rubric #9, score 1) — SEVERITY: HIGH, WORSENS WITH SCALE
- **Missing:** Migration tool, environments, rollback discipline. 197 date-prefixed SQL files applied by hand to the live DB.
- **Costs today:** Repo↔live drift is real (their own `_live_20260807/` snapshot dir + LINEAGE.md's one flagged drift prove it — mitigation is manual verification passes); no staging = every change is tested in production; `*_v2/_v3/_perf` file proliferation shows iterations already straining the convention.
- **To close:** Supabase-native migrations (`supabase db diff`/`db push` or dbt-postgres over the same DB) + a branch/preview-DB flow. Adoption can be incremental: freeze the SQL dir, all *new* changes through migrations. Their golden suite already provides the safety net a migration rollout needs — the hard part is done, oddly.

### PDW-G2 · No human alerting (rubric #7, score 2) — SEVERITY: HIGH, CHEAP TO FIX
- **Missing:** Any push notification when a guard fires. Guards log to tables; the golden suite reds a build nobody watches on weekends; failed Skimmer pushes accumulate silently.
- **Costs today:** 11 failed change-queue pushes sat invisible (measured 2026-08-09); a freshness-guard trip surfaces only when someone opens the status page.
- **To close:** One webhook (Slack/Teams/email) wired to guard-log inserts + workflow failures. Days. This is SDW's triage pattern minus the classification sophistication — the minimal version is a pg_net call on insert into the guard logs.

### PDW-G3 · Credential custody (rubric #10, score 2) — SEVERITY: MEDIUM-HIGH
- **Missing:** Secrets discipline consistent with the rest of their rigor.
- **Costs today:** `warehouse_creds.json` in a synced cloud folder (per golden README); publishable apikey committed in workflow; SUPABASE_MGMT_TOKEN (a full-account token) as the routine SQL path — one leaked secret = whole-account exposure.
- **To close:** (a) move creds to GitHub secrets / Supabase vault (their Phase 3 token-custody plan already points this way — accelerate it); (b) replace mgmt-token SQL path with a scoped service role for routine syncs.

### PDW-G4 · Grain lives in view logic (rubric #2, score 2) — SEVERITY: MEDIUM, QUALITY-OF-LIFE
- **Missing:** Declared fact tables at declared grains; conformed dim structures. The canonical view is a 267-line single object doing episodes + rates + precedence + exclusions at once.
- **Costs today:** Every consumer inherits full view cost; performance iterations (`*_perf`, `_v2`, `_v3`) are symptom treatment; testing any one rule requires the whole view.
- **To close:** Decompose along their own BLUEPRINT.md four-layer design — the target architecture is already written; the gap is executing the refactor. Matviews they already use are the natural landing spots.

### PDW-G5 · Backup restore is untested-in-anger (observed) — SEVERITY: LOW-MEDIUM
- **Missing:** Evidence of a restore drill; the runbook exists (`restore-runbook.html`), an actual restore-from-our-SFTP-copy has never been demonstrated to us.
- **Costs today:** Unknown-unknown. The 2026-08-06→09 backups verify clean, but a backup is proven by a restore, not a checksum.
- **To close:** One drill against a scratch Supabase project from the archived copy; document elapsed time + gaps. (We can offer our archived copies as the drill source — read-only offer, their execution.)

---

## Part 3 — Cross-cutting observations

1. **The two HIGH/irreversible items are on opposite sides:** SDW-G3 (history destroyed nightly — every day of delay is unrecoverable) and PDW-G1 (change management — cost grows with every new SQL file). Both deserve first-slot sequencing in their respective plans.
2. **Four SDW gaps are direct lifts from PDW patterns** (G1 golden/ties, G2 identity ledgers, G4 feed registry, G8 asof) — implementation cost is low because the design risk is already retired by a working reference next door.
3. **Two PDW gaps are direct lifts from SDW patterns** (G2 alerting ← triage, G1 partially ← dbt/PR discipline). The exchange is genuinely bidirectional.
4. **Gaps that interact:** SDW-G2+G3 share the identity-ledger substrate — build once. SDW-G4 gates source onboarding (Samsara/Xima) which PDW has already built clients for — the pattern-mine of their sync code belongs to the onboarding epic, not this study.
