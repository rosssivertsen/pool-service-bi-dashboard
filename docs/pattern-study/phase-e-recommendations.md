# Phase E — Recommendations & Backlog Regroom (SDW)

**2026-08-10 · Derived from Phases A–D. Status: PROPOSED — Ross approves via PR review.**
PDW advisory (Sam's side) is separate: `pdw-advisory-for-sam.md`.

## New backlog items (proposed)

IDs continue existing stream sequences. Effort: S ≤ 1 day · M ≤ 1 week · L > 1 week.

| ID | Item | Effort | Gap | Pattern source |
|----|------|--------|-----|----------------|
| **ETL-10** | **Feed registry + schedule-aware freshness** — `etl.feed_registry` (source, company, max_age_hours, active_hours); freshness check consumes it; unregistered-feed detection vs etl_load_log; retire the early-hours false-WARN | S | G4 | PDW `feed_registry` + `run_skimmer_freshness_guard` (direct lift) |
| **ETL-11** | **Per-company failure isolation + read watchdog** — isolate each company's extract/load; per-company status rows; wall-clock budget on file reads | M | G6 | PDW matrix jobs + `_fetch_hard` |
| **DL-21** | **dbt schema tests, generated** — unique/not_null on every dim key + incremental fact grain; accepted_values on `_company_name` from COMPANY_MAP | S | G1 | Baseline practice; down-payment on ETL-9 item 7 |
| **DL-22** | **Golden invariant suite** — CI (staging mirror) + nightly (prod): fact-grain uniqueness, active-filter identity, COMPANY_MAP coverage, no-cancel-before-create, semantic↔bi_compat row parity. House rule adopted: **anything that has broken twice becomes an invariant** | M | G1 | PDW golden suite + tie guards |
| **DL-23** | **dbt snapshots (SCD2)** on dim_customer, dim_service_location (rate!), stg_route_assignment. ⚠️ **Every day of delay is unrecoverable history** | S–M | G3 | Kimball SCD; PDW *_log siblings |
| **DL-24** | **Identity ledger schema** — `customer_alias` (old→survivor, reason, decided_by, merged_at) + `member_exclusion` (single choke point, audited); staging models honor both | M | G2 | PDW master_id_alias + member_exclusions |
| **DL-25** | **Governed seeds: defined_terms + tag_catalog + entity_registry** — semantic charter as versioned dbt seeds (term, version, definition, rule_ref, approved_by); tag catalog w/ owner + active flag; entity hierarchy w/ validity dates. Charter sign-off event = Ross approves the seed PR | M | G5 | PDW defined_terms + charter process |
| **DL-26** | **`dim_customer_cohort`** — from stg_customer_tag + entity_registry seed; resolves the 495 ambiguous-multi-tag customers; unblocks revenue/churn by acquisition | S | G5 | Own tags + PDW hierarchy |
| **DA-6** | **Freshness badge** — `/api/freshness` (etl_load_log + report freshness logic) + header badge in React + Metabase text card | S | G8 | PDW `warehouse_asof` |
| **RC-9** | **Partner-ledger reconciliation check #9** — PDW cohort ledger (archived governance backup) vs SDW tag counts; surfaces drift daily (currently 1,272 rows) | S | cross | Own harness; data already local at 00:30 |

## Sequencing (proposed waves)

**Wave 0 — this week (all S, two are clock-sensitive):**
1. **DL-23 snapshots** — history is being destroyed nightly; first PR of the wave
2. **ETL-10 feed registry** — gates all future source onboarding; closes the open freshness-guard question
3. **DL-21 schema tests** — one day, ends the zero-tests era
4. **DA-6 freshness badge** — hours; immediate trust ROI

**Wave 1 — next (assertion + identity substrate):**
5. **DL-22 golden suite** (CI gating needs the staging mirror — already exists)
6. **DL-24 identity ledger** → then **DL-25 seeds** → then **DL-26 cohort dim** (strict order; each consumes the previous)
7. **RC-9 partner-ledger check**

**Wave 2 — then:**
8. **ETL-6 provenance columns** (RAISED from backlog — it's the fact-side half of the history story)
9. **ETL-11 isolation/watchdog** · **DL-27?** — no: tie-outs folded into DL-22 scope
10. **ETL-9 full schema governance** (L) — unchanged scope, but DL-21/22 land first as down-payments; ETL-9 items 7–8 consume them

**Explicitly re-ranked, existing items:**
- **ETL-6** Medium→High (history + provenance dual purpose)
- **IN-18** status page exposure: unchanged priority but bundle with DA-6 (same trust theme)
- **SA-M6** (MD5→SHA-256): fold into ETL-10 PR (touching the same files; 20 minutes)

## Proposed deprecations (Ross sign-off required)

| ID | Item | Reason |
|----|------|--------|
| **EIA-5** | Ripple POC scope + vector store design (Pinecone, MS Copilot) | **Superseded by reality:** Ripple Phase 1 is LIVE on pgvector + OpenAI embeddings (ripple.splshwrks.com). The design decision this item proposes was made and shipped differently. |
| **EIA-6** | Vector index pipeline (chunk → embed → Pinecone) | Same — pgvector pipeline exists in production. Any residual scope (embedding docs/enterprise/) belongs to Ripple RP-2.x, not a parallel Pinecone build. |
| **IN-1** | Cloudflare WARP for Manila VA | Was already "awaiting kill-or-keep vs dw-bi mirror" (2026-07-06). Study adds: PDW serves its Manila-equivalent users via CF Access'd dashboards with zero VPN — the dw-bi mirror is the same pattern. **Recommend kill.** |

## What we deliberately do NOT adopt from PDW

- **Loose-SQL change management** — dbt discipline stays; this is our comparative advantage
- **Mgmt-token-as-SQL-path** — our scoped DB roles stay
- **String sentinels** (`'ACTIVE'`, `'NA'`) — real NULLs and dates in all new seeds (entity_registry seed gets typed columns even though PDW's source uses text)
- **Write-back to Skimmer** — SDW stays read-only; the change-queue pattern is noted for a future *separate* tool if ever needed, never inside the warehouse

## Interaction with in-flight streams

- **Ripple (RP-2.x):** unaffected; DL-25's defined_terms seed eventually becomes a Ripple retrieval source (better than YAML — versioned + approved)
- **BI convergence (Invoice next):** BLOCKED-BY DL-24 in spirit — Skimmer↔QBO identity questions will surface immediately; do DL-24 before or alongside
- **New sources (Samsara/Xima/QBO):** HARD-GATED by ETL-10 (registry-first rule); Sam's working sync clients (local clone) are the reference implementations when we get there
