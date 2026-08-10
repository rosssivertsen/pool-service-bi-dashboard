# Phase A — PDW Deep Review: Working Inventory

**Status:** IN PROGRESS · Started 2026-08-10
**Sources (local only, per Lex Immutabilis — nothing touches the AQPN org):**
- Read-only clone: `~/dev/clientwork/splashworks/pdw-readonly/warehouse-sync` @ `9447754` (2026-08-09 21:58 CT), push structurally disabled
- Governance backups: `data/partner-incoming/sftp-greenmill-ci/` (2026-08-06 → 09, 46 tables, 58,095 rows)

## System identity

| Axis | PDW (`warehouse-sync`) |
|---|---|
| Store | Supabase Postgres, project `rdmwvhknizuovfkmszfm` |
| Ingestion | **Hourly API pull** — Skimmer API + QBO/Intuit + Samsara + Xima + Azuga |
| Orchestration | **pg_cron in the warehouse dispatches GitHub Actions** via `ops_sched.dispatch_workflow` → `workflow_dispatch` (GitHub cron was skipping hours) |
| Transformation | Raw SQL files applied to live DB — 197 files, date-prefixed, append-style (`2026-07-19a…n`), NO migration tool |
| Serving | 5 Netlify frontends (admin, console, exec, hub, map) + Supabase edge functions (azuga-live, email-events, manage-users, push-changes) |
| Testing | **Golden suite** — structural invariants against the LIVE warehouse, in CI (push/PR/nightly), low-privilege reader token |
| Write-back | `push-changes` edge function → Skimmer tags (change_queue pattern) |

## Headline mechanisms found (with SDW relevance)

### 1. `core.defined_terms` — versioned in-DB semantic charter ⭐
- Every business definition is a ROW: `(term, version, definition, rule_ref, approved_by, approved_at)`
- `rule_ref` points at the implementing object (`console.v_customer_entity`, `core.mv_recurring_service_month`) — definition and implementation are linked
- Immutable versioning: "Any change = INSERT a new version row; never edit v1, never a silent code change"
- Provenance to a charter Q&A doc: `approved_by = 'Sam (charter Q6)'`
- 13 locked terms incl. Active customer, Churn month (month after EARLIER of last stop / last invoice), New-customer start month (LATER of first-service and first-invoice month), Recurring Service Revenue (fixed-rate component only, chem-plus additive)
- **SDW contrast:** our definitions live in `docs/skimmer-semantic-layer.yaml` + glossary MD — human-readable, joinable by nothing, no version discipline, no approved_by

### 2. Golden suite — invariants as CI, on live data ⭐
- Guard views that must ALWAYS be empty: `v_retired_master_resurrected`, `v_gmp_collisions`, `v_duplicate_customer_candidates`, `v_identity_split_recollapsed`
- Waterfall identity balance: begin + new + acquisitions − lost = ending, every month
- No cancel-before-start; frozen roster must agree with canonical view
- Asserts STRUCTURE not dollar figures (robust to QBO restatements)
- Codified rule: **"anything that has broken twice becomes a test here"**
- **SDW contrast:** 8 reconciliation checks, nightly, pipeline-embedded — good but not CI-gating, not invariant-styled; a bad PR merges green

### 3. Schedule-aware freshness guard ⭐ (answers our open item!)
- `core.run_skimmer_freshness_guard` only evaluates during the sync's ACTIVE hours (UTC 0-3, 11-23 matching dispatch schedule); the overnight gap is never flagged stale
- **Directly resolves SDW's pending freshness-guard question** (manual early-hours runs WARN before Skimmer's ~04:40 UTC publish): encode the expected publish/sync calendar into the guard instead of loosening the definition
- Logs to `core.skimmer_freshness_log` (checked_at, ok, offenders jsonb, note)

### 4. Failure isolation: per-brand matrix, serialized but isolated
- skimmer-sync runs brands as separate matrix jobs: `max-parallel: 1` (no DDL races) + `fail-fast: false` (a jomo death cannot cancel splash) + per-brand timeouts
- Learned from incident (Sam 8/3): sequential brands in one process died silently mid-jomo and starved splash
- `concurrency: cancel-in-progress: false` — queue, never kill a running sync
- **SDW contrast:** nightly ETL processes all companies in one process — same silent-starvation class of risk

### 5. Deterministic-only automation, humans for the rest
- crosswalk-guard: auto-links new QBO customers on deterministic evidence ONLY; everything else → `core.crosswalk_review_queue`; "Never auto-mints, never touches external APIs"
- Same split visible in change_queue (propose → human confirm → push → verify)

### 6. Read-only-by-construction API client
- `sync/qbo_client.py` physically cannot send writes to data endpoints; passed a 9/9 error battery vs Intuit sandbox 2026-07-14
- Invariant enforced in CODE, where SDW enforces via governance docs + RO roles

### 7. Source coverage SDW lacks
- Samsara (fleet), Xima (CCaaS), Azuga (GPS) syncs are BUILT and running hourly/scheduled — these sit on SDW's "candidate new sources" pending list
- QBO depth: AR aging, balance sheet, credit memos, P&L from detail, JE attribution, payments layer (2026-08-07 flurry)

### 8. Data-quality machinery (SQL inventory, to be read in detail)
- `cohort_tie_guard` (+cron), `frozen_feed_guard`, `churn_guardrails`, `warehouse_checks`, `data_quality`, `recon_exceptions`, `ghost_stops`, `data_noise` + noise_cache/compute/resolutions + weekly accounting-team process (charter Q15/Q17)
- `warehouse_asof` — as-of querying (to read)
- `skimmer_fk_indexes`, perf iterations (`*_perf`, `v2`, `v3`)

## Anti-patterns / risks observed (for the PDW advisory doc)
- 197 loose SQL files, no migration tool, no rollback discipline; `_live_20260807/` snapshot dir suggests drift between repo and live DB was already a problem
- Golden README points at a creds file under `00. Master Data/warehouse_creds.json` in a synced folder (custody surface)
- Publishable apikey committed in workflow (acknowledged in README as optional hardening)
- Sentinels as strings (`'ACTIVE'`, `'NA'`) in entity_registry (already noted in backup review)
- Frozen acquisition ledger with no read-back (1,272-row drift measured 2026-08-09)

### 9. `core.feed_registry` — monitoring-completeness invariant ⭐
- Every scheduled feed registered with an explicit `max_age_hours` tolerance; nightly checks fail loudly when one goes quiet
- **The inversion is the genius:** a source that starts succeeding WITHOUT being registered surfaces as `unregistered_feeds` WARN — "future feeds cannot ship unmonitored"
- Deliberate sentinel exception documented (item-classification FAILED = "new items need categorizing", not breakage)
- **SDW contrast:** freshness checks exist per-source but nothing detects an unmonitored source

### 10. Tie guards — one metric computed N ways must agree
- `api.check_cohort_ties`: retention computed by three independent producers (canonical base, compare table, master summary) must tie within tolerance; returns only mismatches
- Accounting tie-out mindset applied to dashboard metrics
- **SDW contrast:** our recon checks compare source→load fidelity; nothing asserts two SDW surfaces agree with each other

### 11. `api.warehouse_asof` — freshness stamped on every UI page
- One shared function returns skimmer/qbo/as-of timestamps; every Pool Deck site header shows "Live · warehouse · <timestamp>"
- **SDW contrast:** our frontend displays no data-currency information at all

### 12. Write-back contract (push-changes edge function)
- The ONLY write path to Skimmer. Admin must RE-ENTER PASSWORD at push time (fresh proof); stale-check current tags vs what the proposer saw; echo-PUT with only tags changed; re-GET to confirm; post-push drift check on non-tag fields
- Careful mechanics — but no push-failure ALERTING (11 failed pushes sat visible only in the console; measured 2026-08-09)

### 13. Backup scope = irreplaceability criterion
- `warehouse_backup.py`: captures "everything a rebuild could NOT regenerate" (identity decisions, grants, audit logs, manual maps); deliberately EXCLUDES reconstructable data (covered by Supabase PITR)
- Pinned SFTP host key; SFTP-subsystem-only (works in chroot); optional GPG; rotate-to-30; run recorded in sync_run either way; type-safe restore runbook
- This is the producer of the files in OUR `incoming/` drop-off

### 14. Ingestion engineering (sync_skimmer.py)
- Hard wall-clock watchdog in a worker thread — urllib's timeout is per-recv, so dripping responses hung two prior guards; on timeout the response is ABANDONED not closed (closing drains at drip speed = unbounded hang; "verified against a local dripping server")
- Cloudflare 520–524 treated as a distinct retry class with longer backoff (learned from the 2026-07-23 Skimmer outage)
- Schema-introspecting upserts: target columns read from information_schema at run time; API-supplied columns update, export-only columns never touched → tolerant of additive schema drift (SDW's ETL-9 concern, solved differently)
- Invoice-shape validation: malformed rows are never written (2026-07-14 shadow-invoice bug)
- `landing.sync_run` ledger: one row per run (source, brand, detail, status) — feeds freshness guard + status page

### 15. Process/governance documents (docs/)
- **BLUEPRINT.md** (v1.0, 2026-08-07) — target-state architecture: 4 layers (raw → identity/MDM → conformed core → serving), master-ID hubs, conformed dims, "every new source enters through the same three-step recipe; adding a system is mechanical, not a project." Explicitly named as MDM hub-and-spoke on a layered warehouse
- **LINEAGE.md** (v1.1) — current-state map, **verified against live** (38/38 objects confirmed, cited counts tie, one drift found and flagged inline). Companion to the charter; "definitions never fork"
- **RULINGS_2026-07-15.md** — durable decision log with status markers (APPLIED / LOCKED / UNCONFIRMED); e.g. acquisition CMs post to balance sheet not revenue; JOMO sales receipts count in revenue
- **customer-data-definitions{,-ANSWERED}.md** — the charter Q&A pair that became `core.defined_terms`
- `tag_update_log_*.csv` — bulk-change artifacts committed to the repo (audit trail of mass tag operations)
- `defined_terms` now at **31 terms** live (v1 file showed 13 — the charter grew)

## Consciously skipped (diminishing returns for this study)
- Frontend internals (5 Netlify apps) — patterns of interest (asof header, console queue UX) already captured via their SQL/function contracts
- `_live_20260807/` full drift diff — its existence + LINEAGE.md's verified-against-live pass already establish both the problem (drift happens) and their mitigation (verification passes)
- Azuga/Samsara/Xima sync internals — noted as existing, working reference implementations; detailed read deferred to when SDW actually onboards those sources

## Phase A verdict (feeds Phases C/D)
PDW's strengths are **operational learning loops** (every incident becomes a guard, a registry, or a test) and **decision governance** (charter → versioned terms → rule_ref → guard views → golden CI). Its weaknesses are **change management** (197 loose SQL files, no migration tool, repo↔live drift) and **alerting** (guards log and fail builds, but humans aren't paged; failed pushes sit silent). SDW is the mirror image: strong change management (dbt, PRs, branch discipline) and alerting (triage → Slack), weaker on invariant testing, semantic governance as data, and feed-completeness monitoring.
