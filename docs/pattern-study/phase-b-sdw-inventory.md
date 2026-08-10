# Phase B — SDW Self-Review: Working Inventory

**Status:** IN PROGRESS · 2026-08-10 · Same lens and categories as Phase A (`phase-a-pdw-inventory.md`)

## System identity

| Axis | SDW (this repo) |
|---|---|
| Store | Postgres 16 + pgvector, self-hosted (Docker, Hostinger VPS) |
| Ingestion | **Nightly extract pull** — Skimmer publishes SQLite to OneDrive ~04:40 UTC; pipeline 05:30 UTC (sync → ETL → dbt → reconciliation → health) |
| Orchestration | VPS crontab (05:30 pipeline, 06:00 SFTP publish, 02:30 audit retention, 00:30 partner archive) |
| Transformation | **dbt** — 55 models: 21 staging, 18 warehouse, 14 semantic, 2 bi_compat; PR-gated, branch-per-stream discipline |
| Serving | React SPA + FastAPI (NL→SQL via Claude), Metabase BI, Ripple RAG chat; Cloudflare Access on all endpoints |
| Testing | 7 Python unit-test files (ETL mechanics) + 65 frontend tests; **ZERO dbt schema tests**; 8 reconciliation checks (Python, nightly, non-gating) |
| Write-back | None (read-only warehouse; SELECT-only API guardrails) |

## Strengths (verified)

### 1. Change management — PDW's weakest area is our strongest
- dbt-managed transformations, git-PR flow, one-branch-per-stream, prod tracks `main`
- ETL migrations dir; schema fingerprinting seeded (`schema_contract.py`, full rollout = ETL-9)

### 2. Failure triage → humans, with enrichment
- `etl/triage.py`: signature KB, per-step impact, fix actions → `etl_incident_log` + `data/incidents/*.json` + Slack #alerts + recovery notifications; Haiku enrichment for unknown classes
- PDW has nothing comparable — guards log, nobody is paged

### 3. Nightly report with delivery-integrity verification
- `etl/report.py`: EXIT-trap coverage, freshness derived from source mtime per company, SFTP drop-off QC with JSON-manifest verification (VERIFIED/MISSING/MISMATCH/UNREADABLE), bounded listing that never elides failures

### 4. Reconciliation (8 checks, `etl/reconcile.py` CHECKS list)
- Source→load fidelity exact per company+table; fact version-inflation WARN (DL-15 pending)
- Unions generate from `COMPANY_MAP` — one registry drives ETL + reconcile (good registry discipline)

### 5. Security posture
- Audit schema isolated from RO role; PII redaction @90d, deletion @365d; CF Access + tunnels; anonymized staging mirror with fail-closed leak check; chrooted partner SFTP with transfer logging + sidecar verification + custody archive

### 6. Data-source registry discipline
- `etl/config.py` COMPANY_MAP as single onboarding point; unmapped extracts skipped loudly (CLERMONT onboarding proved the runbook)

## Weaknesses (verified, honest)

### 1. ZERO dbt tests — the invariant gap ⭐
- `grep -rl "tests:" dbt/models --include='*.yml'` → **0 files**. Not even unique/not_null on dimension keys
- All safety lives in Python reconciliation (nightly, after the fact, non-gating) — a bad PR merges green and runs against prod that night
- PDW contrast: golden CI on every push/PR + nightly; "broken twice = test"

### 2. Semantics are prose, not data
- 890-line semantic YAML + 1,612-line data dictionary + enterprise glossary MD — rich, but joinable by nothing, no versioning discipline, no approved_by, no rule_ref to implementing model
- PDW contrast: `core.defined_terms` — 31 versioned rows, provenance to a signed-off charter, each with rule_ref

### 3. No dimension history (SCD0 rebuild)
- Dims rebuilt nightly; cancellation date inferred from `updated_at` (workaround for missing history)
- Rolling 6-month window + full raw replacement = upstream merges/deletions erase silently (proved: 101 PDW-adjudicated merges left zero trace here)

### 4. No monitoring-completeness mechanism
- Freshness checks exist per company, but nothing detects an unmonitored feed; no feed registry; a new source could ship without alerting and nobody would know
- Open freshness-guard question (early-hours false WARN) — PDW's schedule-aware guard is the answer pattern

### 5. No cross-surface tie guards
- Nothing asserts app/API, Metabase, and BI-compat views agree on the same metric; BI convergence is manual (report-by-report vs report-catalog.md)

### 6. Identity is per-source only
- Joins on (id, _company_name); no conformed customer identity across systems (Skimmer↔QBO); no exclusion registry for non-customers (PDW: `core.member_exclusions` single choke point, console-managed, audited)
- No entity/org hierarchy with validity dates; `_company_name` is flat and eternal

### 7. Tag vocabulary ungoverned
- 40+ free-text tags/company, no catalog, no owner, no active flag; 495 active customers ambiguous-multi-cohort (measured 2026-08-09)

### 8. UI shows no data currency
- No as-of stamp anywhere user-facing; PDW stamps every page header

## Verifications (complete, 2026-08-10)
- **8 reconciliation checks enumerated:** active_customer_count · payment_count · invoice_item_count · service_stop_count · payment_total_amount · route_skip_day_of_count · source_load_vs_raw (exact, per company+table) · fact_service_stop_duplicate_rows (grain-dup detector; text implies DL-15 landed — confirm in Phase E)
- **Semantic YAML IS machine-consumed** — `schema_context.py` loads it into the AI system prompt. So it's data to the AI layer but not to dbt/SQL: not joinable, unversioned, no approved_by. The gap is narrower than "prose only" but the governance criticism stands
- **Incremental discipline is good:** 10 incremental models, all with composite `unique_key` incl. `_company_name`; fact_service_stop carries the DL-15 dedup grain
- **Frontend freshness display: confirmed absent** (no as-of/freshness/last-updated in any tsx)
- **Backlog surveyed** (271 lines): ETL-6 (row provenance), ETL-8 (recon snapshots), ETL-9 (schema governance, L — overlaps feed-registry + contract-driven dbt tests), EIA-1..6 (glossary machine-readability), IN-18 (status page), IN-19 (tooling extraction) all intersect Phase B weaknesses → Phase E regroom material

## Phase B verdict
SDW's spine — change management, alerting, security, registry-driven onboarding — is production-grade. Its gaps cluster in one theme: **nothing asserts truth before or after deployment**. No dbt tests (pre-merge), no invariant guards (post-load), no tie-outs (cross-surface), no semantic versioning (definitional), no dimension history (temporal). PDW's entire strength is exactly this missing assertion layer. The exchange is symmetric: they need our spine, we need their guards.
