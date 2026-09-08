# Splashworks Data Warehouse — Backlog

**Project:** Splashworks Enterprise Data Platform
**Last Updated:** 2026-07-17

---

## Streams

| Prefix | Stream | Description |
|--------|--------|-------------|
| DL- | Data Layer | dbt warehouse models, reports, dimensions |
| AQ- | AI Query | Query intelligence, repair, RAG |
| EIA- | Enterprise Info Architecture | Glossary, standards, agent-readiness, Ripple |
| DA- | Dashboard | Frontend dashboard features |
| IN- | Infrastructure | VPS, networking, security |
| SX- | Scrape → Export Triage | UI-only web-scrape deliverables evaluated for warehouse report/export sourcing |

---

## Skimmer Scrape → Export/Report Triage

**Intake rule (established 2026-05-28):** Every Skimmer (or other UI-only) web scrape produced for a client is logged here as a candidate warehouse report/export. The warehouse is the single source of truth for **source-document traceability** — a scrape is a signal that a report/export may belong in SDW. Triage each:

- **(a) Warehouse-derivable** — the underlying data is in the nightly extract → build as a `DL-` report/export and retire the recurring scrape. One lineage, auditable.
- **(b) UI-only / not in extract** — evaluate as a new `ETL-` ingestion source, *or* consciously accept it as a permanent one-off scrape.

One-off scrapes remain acceptable. This log exists so each scrape is **consciously dispositioned, not silently repeated** — and so that when a report can come from the warehouse, source traceability collapses to a single source.

| ID | Source page | Org(s) scraped | In nightly extract? | Disposition candidate | Effort | Notes |
|----|-------------|----------------|---------------------|-----------------------|--------|-------|
| SX-1 | `/Client/Jobs` | Splashworks Ocala (= AQPS?), also exists for JOMO | **No `Job` table** — extract has WorkOrder / Quote / Invoice / Payment but not the Job wrapper entity | (a) reconstruct Job as a `DL-` report by joining WorkOrder + Invoice + Payment + Customer; OR (b) add `Job` to the ETL extract if Skimmer's SQLite exposes it | M | First scrape 2026-05-28 (139 jobs, Splashworks Ocala, $122,770 total). **Confirm:** (1) is Skimmer's "Job" entity in the 44-table extract under another name? (2) does Splashworks Ocala = AQPS legal entity? (3) is "The Pool Deck" org a 3rd entity outside the warehouse? Scraper: `invoice-entry-qbo-skimmer/scripts/scrape-jobs.js`. |
| SX-2 | `/Client/Integrations/QBO` (Activity tab) | JOMO | **No** — UI-only Skimmer↔QBO sync-event log, not a Skimmer DB table | (b) new `ETL-` source: scrape → `fact_qbo_sync_event`. See EIA sync-observability proposal. | M | First scrape 2026-05-27 (54,520 rows / 180d JOMO, 8.4% error rate). The error subset = the `rpa-disposition-agent` input queue. Ties to the EIA gap: the QBO↔Skimmer integration is marked "real-time/healthy" but has no observability layer in the warehouse. Scraper: `invoice-entry-qbo-skimmer/scripts/scrape-qbo-activity.js`. |

---

## Priority: High

### Enterprise Information Architecture

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| EIA-1 | Agent-ready frontmatter on all glossary/standards docs | Docs | S | YAML frontmatter: entity, type, systems, system_of_record, related |
| EIA-2 | Enterprise index manifest (`enterprise-index.yaml`) | Docs | S | Auto-discoverable catalog of all EIA docs for agents |
| EIA-3 | Invoice + Payment glossary entities | Docs | M | Cross-system mapping (Skimmer → QBO → Warehouse) |
| EIA-4 | Technician + Route glossary entities | Docs | S | Skimmer-only entities, warehouse mapping |
| EIA-5 | Ripple POC scope + vector store design | Design | M | MS Copilot agent, Pinecone embeddings, first use cases |
| EIA-6 | Vector index pipeline (chunk → embed → Pinecone) | Backend | M | Ingest docs/enterprise/ into searchable index |

### ETL — Historical Accumulation

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| ~~ETL-1~~ | ~~**Incremental fact accumulation** — switch dbt fact tables to `incremental` materialization with dedup keys~~ | ~~dbt + ETL~~ | ~~M~~ | ~~DONE 2026-03-18. All 10 facts incremental. Also fixed missing `_company_name` joins + added `service_stop_entry_id` to dosage facts.~~ |
| ~~ETL-2~~ | ~~**Load RouteSkip + SkippedStopReason** — add to ETL raw sources~~ | ~~ETL~~ | ~~S~~ | ~~DONE 2026-03-18. Already in raw (ETL loads all 44 tables). Added dbt sources + staging models.~~ |
| ~~ETL-3~~ | ~~**Load RouteMove** — add to ETL raw sources~~ | ~~ETL~~ | ~~S~~ | ~~DONE 2026-03-18. Same — already in raw. Added dbt source + staging model.~~ |
| ETL-4 | **Load Equipment tables** — EquipmentItem, InstalledItem, PartCategory, PartMake, PartModel | ETL | S | New raw tables needed for DL-6 (dim_equipment) |
| ~~ETL-5~~ | ~~**Nightly reconciliation check** — compare raw vs warehouse counts/totals, JSON report, pass/fail in pipeline~~ | ~~ETL~~ | ~~S~~ | ~~DONE 2026-03-26. 6 checks (active customers, payments, invoice items, service stops, payment totals, route skips). Runs nightly after dbt.~~ |
| ETL-6 | **Add `_loaded_at` + `_extract_date` to fact tables** — row-level provenance for incremental facts | ETL | S | Phase 2 of source traceability. Enables "when did this row enter the warehouse?" |
| ETL-7 | **Row-level trace CLI** — given a Skimmer ID, trace it through raw → staging → warehouse → semantic | ETL | M | Phase 2 of source traceability. `./cli/trace-record.sh payment abc123 AQPS` |
| ETL-8 | **`rpt_reconciliation` dbt model** — point-in-time snapshots of source vs warehouse totals with variance | dbt model | S | Phase 3 of source traceability. Auditable trail for compliance. |
| ETL-9 | **Schema governance rollout** — full CTRL-01/02/04/05 implementation on top of hotfix seed | ETL + dbt | L | Builds on `docs/data-governance/` scaffold landed 2026-04-20. Scope: (1) YAML contract loader + validator in `etl/schema_contract.py`, (2) drift detector + `etl_schema_drift` population, (3) atomic pipeline gate in `nightly-pipeline.sh` (drift → abort before any load), (4) Slack `#alerts` alerting for drift events, (5) append-only triggers + `auditor_ro` role on evidence tables, (6) `union_companies()` macro rewrite to emit explicit column lists from contracts, (7) dbt tests generated from contracts, (8) migrate all 45 Skimmer tables from pre-governance → governed (one contract file per table, reviewed PR per migration). **Policy:** `docs/data-governance/policy.md` (*Lex Immutabilis*). **Drives:** future QBO + Zoho onboarding per `procedures/new-source-onboarding.md`. |

### Data Layer — Warehouse Models

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| ~~DL-1~~ | ~~`dim_service_location` — address, city, state, zip, rate, rate_type, labor_cost~~ | ~~dbt model~~ | ~~S~~ | ~~DONE 2026-03-12~~ |
| ~~DL-2~~ | ~~`rpt_customer_360` — denormalized customer + locations + service stats + payments~~ | ~~dbt model~~ | ~~M~~ | ~~DONE 2026-03-14~~ |
| ~~DL-3~~ | ~~`rpt_service_history` — service visits with customer/tech/pool names (no IDs)~~ | ~~dbt model~~ | ~~M~~ | ~~DONE 2026-03-15~~ |
| ~~DL-4~~ | ~~`rpt_payment_summary` — payments with customer names, monthly aggregation~~ | ~~dbt model~~ | ~~S~~ | ~~DONE 2026-03-15~~ |
| DL-5 | `rpt_profitability` — profitability with customer names (no IDs) | dbt model | S | Metabase-friendly wrapper around semantic_profit |
| DL-6 | `dim_equipment` — equipment/parts per service location | dbt model | M | Depends on ETL-4. Zero coverage currently. |
| DL-7 | Metabase schema cleanup — hide raw/staging/IDs, rename columns | Config | S | Admin > Table Metadata; no code changes |
| ~~DL-10~~ | ~~`fact_invoice_item` — line-item revenue analysis, product mix, cross-sell~~ | ~~dbt model~~ | ~~S~~ | ~~DONE 2026-03-18. 16,517 rows.~~ |
| ~~DL-11~~ | ~~`fact_route_skip` — skipped service tracking with reasons, revenue leakage~~ | ~~dbt model~~ | ~~S~~ | ~~DONE 2026-03-18. 806 rows (day-of + pre-planned).~~ |
| ~~DL-12~~ | ~~`fact_route_move` — schedule disruption tracking, tech reassignment patterns~~ | ~~dbt model~~ | ~~S~~ | ~~DONE 2026-03-18. 3,510 rows.~~ |
| DL-13 | `fact_equipment_install` — equipment lifecycle, replacement cycles, parts spend | dbt model | M | Depends on ETL-4 + DL-6. |
| DL-20 | **Recurring Service Checklist report** — per-stop, per-item completion + reason | dbt model | M | **BLOCKED on data.** Not in the nightly extract; Skimmer API has no checklist endpoint (re-verified live 2026-07-17 — `Routes`/`ServiceStops`/`Checklists`/`ServiceHistory` all 404). Data exists only in Skimmer's UI Service History export. Unblock = Option C (scheduled CSV → OneDrive, needs Skimmer). Scaffold + correspondence preserved in `docs/plans/blocked-features/`. |
| ~~DL-14~~ | ~~`rpt_active_routes` + `cli/export-active-routes.sh` — CEO-recurring active routes export. Vendor-canonical filter (Glenn/Skimmer 2026-04-22). Observational service-state labels.~~ | ~~dbt + CLI~~ | ~~S~~ | ~~DONE 2026-04-22. Fills Skimmer Route Dashboard export gap (native only supports screenshots).~~ |
| ~~DL-15~~ | ~~**`fact_service_stop` duplicate-row bug** — NULL `service_stop_id` in the incremental unique_key never matched on merge, so unmatched route stops re-appended every night (JOMO 335,804 vs 99,739 real, 3.5x).~~ | ~~dbt model~~ | ~~M~~ | ~~**DONE 2026-07-15 (PR #29).** Fix: `coalesce(service_stop_id, route_stop_id)` (unique per date). One-time in-place dedup migration (~240k rows, NOT --full-refresh — preserves aged-out history). Reconcile check rewritten `version_inflation`→`fact_service_stop_duplicate_rows` (old one miscounted legit fan-out); now 0 dupes, 8/8 pass. rpt_service_history 377,708→140,871.~~ |

### App — AI Query Intelligence (The Moat)

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| ~~AQ-4~~ | ~~**Semantic rewriter** — two-stage Haiku rewriter + Sonnet generator with confidence signals, industry metric catalog, unanswerable detection~~ | ~~Backend + Frontend~~ | ~~L~~ | ~~DONE 2026-03-13. 20 metrics, confidence badges, unanswerable detection.~~ |
| ~~AQ-5~~ | ~~**Few-shot examples in system prompt** — 13 verified queries as SQL examples~~ | ~~Backend~~ | ~~S~~ | ~~DONE 2026-03-12~~ |
| ~~AQ-6~~ | ~~**ETL cron automation** — nightly pipeline: rclone sync → Python ETL → dbt → health check~~ | ~~Backend/Infra~~ | ~~M~~ | ~~DONE 2026-03-12. Cron at 1:15 AM UTC.~~ |
| AQ-7 | **SQL repair layer expansion** — add more repair strategies (missing table aliases, ambiguous columns, etc.) | Backend | S | Current: GROUP BY + type cast. Extend as new error patterns emerge. |
| AQ-8 | **Pool Deck knowledge base RAG** — embed Skimmer help articles for industry vocabulary enrichment | Backend | M | Source: https://thepooldeck.getskimmer.com/knowledge-base |
| AQ-9 | **Pool Deck community content** — ingest crowdsourced pool service operator knowledge | Backend | M | Source: https://thepooldeck.getskimmer.com/community |

### App — AI Query UX

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| AQ-1 | Query history / chat history (conversation-style UX) | Frontend | L | New component, API endpoint for threading |
| AQ-2 | Display generated SQL explanation alongside results | Frontend | S | Already returned by API; not shown prominently |
| AQ-3 | Retry/refine button on query errors | Frontend | S | "Try again" with modified prompt |

### App — Dashboard Improvements

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| DA-1 | JSON dashboard export/import for sharing | Frontend | S | Serialize/deserialize localStorage |
| DA-2 | Individual chart PNG export | Frontend | S | html2canvas per card |
| DA-3 | Dashboard templates library | Frontend | M | Preset dashboards for common use cases |
| DA-4 | PDF export with formatted report layout | Frontend | M | jsPDF + layout formatting |
| DA-5 | Dashboard duplication | Frontend | S | Clone existing dashboard |

### Infrastructure

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| IN-1 | Cloudflare WARP for Power BI remote access | Config | M | VA in Manila needs Power BI connectivity |
| ~~IN-2~~ | ~~Read-only Postgres users for Metabase + Ripple~~ | ~~Config~~ | ~~S~~ | ~~DONE 2026-03-26. `ripple_rw` + `metabase_ro` created. Ripple switched to restricted user.~~ |
| IN-3 | Deploy UI refinements to VPS (UI.11) | Deploy | S | Number formatting, date handling, starter prompts |
| ~~IN-7~~ | ~~**Ripple CF Access auth middleware**~~ | ~~Security~~ | ~~S~~ | ~~DONE 2026-03-26. CloudflareAccessMiddleware added, JWT forwarded in Nginx.~~ |
| ~~IN-8~~ | ~~**Use CF-Connecting-IP for audit logging**~~ | ~~Security~~ | ~~S~~ | ~~DONE 2026-03-26. Prefers CF-Connecting-IP over spoofable X-Forwarded-For.~~ |
| ~~IN-10~~ | ~~**VPS migration** — move all production services from 76.13.29.44 (KVM-2, personal Hostinger) to 2.24.202.170 (KVM-4, splashworks Hostinger)~~ | ~~Migration~~ | ~~L~~ | ~~**DONE 2026-06-25.** Cutover complete — warehouse + all 8 services live on `2.24.202.170` (tailnet `100.124.108.126`), counts matched source exactly, tunnel stable on `--protocol http2`, Power BI repointed, Metabase H2 migrated + volume-backed. Source stopped + retained (rollback). Runbook Cutover Log: `docs/runbooks/2026-05-vps-migration.md`. **Tail:** day-1 ETL verify, source decommission decision.~~ |

### Infrastructure — Security, Partner Delivery & Observability (2026-07)

Shipped 2026-07-14 → 07-17 (see `docs/SECURITY_AUDIT_2026-07-14.md` + `docs/runbooks/2026-07-1*`).

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| ~~IN-11~~ | ~~**Audit-log isolation (SECURITY_AUDIT MEDIUM-1)**~~ | ~~Security~~ | ~~S~~ | ~~DONE 2026-07-14 (PR #24). `query_audit_log`+`etl_incident_log` moved `public`→`audit` schema; RO API role can INSERT but not SELECT (closed cross-user PII read via /api/query/raw). Deployed prod+staging.~~ |
| ~~IN-12~~ | ~~**Audit-log PII retention (MEDIUM-2)**~~ | ~~Security~~ | ~~S~~ | ~~DONE 2026-07-14 (PR #25). Redact PII free-text @90d, delete rows @365d; nightly cron. Keeps metadata (the audit trail), sheds the liability.~~ |
| ~~IN-13~~ | ~~**Greenmill SFTP delivery**~~ | ~~Infra~~ | ~~M~~ | ~~DONE 2026-07-14→17 (PRs #26/#28/#30-31). Chrooted, key-only, shell-less accounts (`sftp-greenmill` + `-ci` for their GitHub Actions), fail-closed per-jail entitlements, nightly publish w/ checksummed manifest, per-login Slack access alerts. Replaced Sam's Entra app-registration ask. Runbook `2026-07-14-greenmill-sftp.md`.~~ |
| ~~IN-14~~ | ~~**Nightly ingestion report + fix chronic 24h data lag**~~ | ~~ETL/Infra~~ | ~~M~~ | ~~DONE 2026-07-14 (PR #27). Pipeline ran 01:15 UTC but Skimmer publishes ~04:40 → every green run pulled yesterday's data. Cron → 05:30. EXIT-trap report (status+stats+**freshness guard**) via email (Resend) + Slack.~~ |
| ~~IN-15~~ | ~~**Status dashboard (hosted + email)**~~ | ~~Infra~~ | ~~M~~ | ~~DONE 2026-07-17 (PR #31). `etl/status_page.py` renders the whole pipeline (stages, reconciliation, delivery) from live state → email body (Outlook-safe table build) + hosted page (nginx behind CF Access). Prod + personal box. Reusable across clients.~~ |
| ~~IN-16~~ | ~~**Rotate `splashworks_ro` credential**~~ | ~~Security~~ | ~~S~~ | ~~DONE 2026-07-14. Rotated (was exposed in a session transcript); verified old value rejected on the scram path.~~ |
| IN-17 | **Enable `ufw` + tighten `pg_hba` localhost trust** | Security | S | SECURITY_AUDIT_2026-07-14 LOWs. ufw inactive on the shared box; pg_hba `trust`s localhost. Coordinate with the jomo-inventory owner (shared host). Add Greenmill source-IP allowlist if they provide static egress IPs. |
| IN-18 | **Expose `status.splshwrks.com`** (Cloudflare dashboard) | Infra | S | Add tunnel public hostname → `localhost:8090` + Access app attaching the existing policy. Container + generated page already live. Runbook `2026-07-17-status-dashboard.md`. |
| IN-19 | **Extract nightly-DW tooling to `enterprise-templates`** (CCE + other clients) | IP/Tooling | M | `reconcile.py` + `report.py` + `status_page.py` are client-agnostic; lift `COMPANY_MAP`/`COMPANY_ORDER`/`CHECK_LABELS`/check-list to config, scaffold as a `data-warehouse-nightly` module. |
| IN-21 | **Migrate agent secret access to Bitwarden Secrets Manager (`bws`)** | Security/Tooling | M | Target state ("C"): machine account + `BWS_ACCESS_TOKEN`, no master password ever on disk. Interim ("B", set up 2026-07-17): personal-vault API-key login (`~/.bw-creds`, `bw-session` helper) + manual unlock per session. Move the Skimmer/DB/webhook secrets into Secrets Manager so scripts pull via `bws` instead of `.env`/plaintext. Retires `skimmer-api-keys.txt`. |
| IN-22 | **Restricted archive destination for BBSI payroll/HR drop-off** | Security/Infra | S | **Opened 2026-09-08 as the direct consequence of deploying `ARCHIVE_EXCLUDE=sftp-bbsi`.** BBSI is now excluded from the shared partner archive (correct — it is general-purpose and other tooling reads it), which means BBSI files have **no durable copy anywhere**: the only copy sits in `/srv/sftp/sftp-bbsi/incoming/`, which is partner-writable by definition. Whoever holds that key can overwrite or delete it and our copy goes with it — the same "a writable location is not a backup" problem `archive-incoming.sh` solved for Greenmill, reopened for the most sensitive account. **Design constraint that rules out simply pointing the existing script at a new directory:** `archive-incoming.sh` only copies payloads whose sidecar `*.manifest.json` verifies, and BBSI sends no manifests — so it would archive nothing and report success. Needs its own integrity signal: either the `<file>.csv.sha256` sidecar being proposed to BBSI (uploaded LAST as the transaction boundary — see `reference_partner_file_transfer_conventions`), or a settle-time heuristic if they will not add one. Requirements: root-owned dest, perms tighter than the shared archive's 0750/0640, its own retention clock (payroll PII should not be kept indefinitely — contrast IN-12's 90d/365d pattern), encryption at rest (runbook OPEN item 5), and reconciliation so a silent no-op is detectable. Runbook: `docs/runbooks/2026-08-10-bbsi-sftp.md`. **Must be live before BBSI's first real report lands.** |

### Security Audit Findings (2026-03-28) — Open

| ID | Severity | Item | Category | Effort | Notes |
|----|----------|------|----------|--------|-------|
| SA-M1 | Medium | SQL validation regex bypass via comments — strip block comments before regex check | Security | S | `api/services/query_executor.py`. Mitigated by read-only DB user. |
| SA-M2 | Medium | Rate limiter uses spoofable client IP — switch to CF-Connecting-IP | Security | S | `api/rate_limit.py`. Same fix pattern as IN-8. |
| SA-M3 | Medium | Metabase using H2 embedded DB — migrate to Postgres-backed Metabase | Security | M | `docker-compose.yml:64-75`. H2 has known CVEs, not backed up with pg volume. |
| SA-M4 | Medium | Audit logger shares main DATABASE_URL — consider separate audit DB user | Security | S | `api/services/audit_logger.py`. Privilege separation concern. |
| SA-M5 | Medium | Frontend Dockerfile uses `npm install` instead of `npm ci` | Security | S | Supply chain risk from dynamic resolution. |
| SA-M6 | Medium | MD5 used for ETL file checksums — switch to SHA-256 | Security | S | `etl/extract.py:39-44`. MD5 is deprecated. |
| SA-M7 | Medium | Ripple `ripple_rw` has overly broad CREATE DATABASE permission | Security | S | Pre-create ripple schema, remove CREATE ON DATABASE grant. |
| SA-L2 | Low | No CSRF token on mutation endpoints | Security | S | Mitigated by CF Access + CORS. |
| SA-L3 | Low | Unquoted shell variables in deploy script | Security | S | `scripts/deploy.sh:53`. |
| SA-L4 | Low | Docker containers run as root | Security | S | Add USER directive to Dockerfiles. Overlaps PH-5. |
| SA-L5 | Low | `firebase-debug.log` committed to repo | Security | S | Remove and add to .gitignore. |
| SA-L6 | Low | FastAPI docs endpoint exposed in production | Security | S | `api/main.py:13`. Disable /docs and /redoc in production. |

---

## Priority: Medium

### App — UI Polish

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| UP-1 | Self-improving prompt tracking (analytics on prompt clicks) | Full stack | M | New tracking table, API endpoint |
| UP-2 | Database Explorer — show warehouse schema with descriptions | Frontend | S | Help users understand available data |

### Data Layer — Extended Coverage

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| DX-1 | Route optimization models | dbt model | L | Route scheduling, stop ordering |
| DX-2 | LSI calculation model | dbt model | M | Langelier Saturation Index from chemical readings |
| DX-3 | Product categories / chemical product dimension | dbt model | S | Categorize dosage entries |
| DX-4 | Tax configuration model | dbt model | S | Tax rates per jurisdiction |

### Data Layer — Future Data Sources (KPIs blocked on new integrations)

| ID | KPI | Blocked On | Data Source | Notes |
|----|-----|------------|-------------|-------|
| DS-1 | Technician utilization rate (billable vs paid hours) | No clock-in/clock-out | Time & attendance (e.g., Homebase, Deputy) | Target: 65-75% utilization |
| DS-2 | First-time fix / callback rate | No callback tracking | CRM or dispatch system | Inverse = repeat visit rate |
| DS-3 | Drive time per job / on-time arrival rate | No GPS or appointment windows | Telematics (e.g., GPS Trackit, Azuga) | High drive time = routing/territory issues |
| DS-4 | Route density (stops per mile) | No geocoding | Telematics + geocoded addresses | Tighter density = better margins |
| DS-5 | CSAT / NPS scores | No survey data | CRM or survey tool (e.g., Zoho, Jobber) | Tech-level and route-level |
| DS-6 | Booking rate / calls handled / abandoned | No call center data | Phone system (e.g., Xima, RingCentral) | CSR performance |
| DS-7 | Lead-to-booking conversion | No CRM pipeline | CRM (e.g., Zoho CRM) | Marketing ROI, cost per booked job |
| DS-8 | Customer acquisition cost | No marketing spend data | QBO + CRM | Marketing spend / new customers |
| DS-9 | Membership / contract retention rate | Partial — have churn | CRM contract tracking | Renewal rate over time |

---

## Priority: Low

### Pre-Production Hardening

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| PH-1 | Create `splashworks` system user on VPS | Security | S | Move file ownership from root |
| PH-2 | Run Docker Compose as non-root | Security | S | Add to docker group |
| PH-3 | Run cloudflared as non-root | Security | S | systemd `User=` directive |
| PH-4 | Move cron to non-root user | Security | S | Non-root crontab |
| PH-5 | FastAPI/frontend containers run as non-root | Security | S | Dockerfile USER directive |
| PH-6 | Review `.env` permissions and secrets management | Security | S | File permissions, vault consideration |

### Legacy Fixes

| ID | Item | Category | Effort | Notes |
|----|------|----------|--------|-------|
| LF-1 | Fix critical bugs (Dropbox token revocation, SQL injection) | Security | M | Deferred from Phase 0; apply before production |

---

## Completed

| ID | Item | Completed |
|----|------|-----------|
| ~~META-1~~ | Metabase connected (bi.splshwrks.com) | 2026-03-11 |
| ~~AUTH-1~~ | Cloudflare Access (GitHub + Google + OTP) | 2026-03-11 |
| ~~AQ-7a~~ | SQL repair layer v1 (GROUP BY + type cast auto-fix) | 2026-03-12 |
| ~~DL-8~~ | Route assignment semantics (stg_route_assignment + system prompt + verified query) | 2026-03-12 |
| ~~AQ-5~~ | Few-shot examples — 13 verified queries in system prompt | 2026-03-12 |
| ~~AQ-6~~ | ETL cron automation — nightly-pipeline.sh (sync → ETL → dbt → health) | 2026-03-12 |
| ~~DL-1~~ | dim_service_location — added address column, updated system prompt | 2026-03-12 |
| ~~DL-9~~ | Customer lifecycle semantics (cancelled/new customer terms + dim_customer dates) | 2026-03-12 |
| ~~UI.11~~ | UI refinements deployed to VPS (starter prompts, dashboards, charts) | 2026-03-12 |
| ~~AQ-4~~ | Semantic rewriter — Haiku preprocessing, confidence badges, unanswerable detection, improved errors | 2026-03-13 |
| ~~DL-2~~ | rpt_customer_360 — denormalized customer profile with LTV | 2026-03-14 |
| ~~DL-3~~ | rpt_service_history — denormalized service visits (69,186 rows) | 2026-03-15 |
| ~~DL-4~~ | rpt_payment_summary — denormalized payments (12,247 rows) | 2026-03-15 |
| ~~ETL-1~~ | Incremental fact accumulation — all 10 facts switched to incremental + dedup keys | 2026-03-18 |
| ~~ETL-2~~ | RouteSkip + SkippedStopReason — dbt sources + staging models | 2026-03-18 |
| ~~ETL-3~~ | RouteMove — dbt source + staging model | 2026-03-18 |
| ~~DL-10~~ | fact_invoice_item — line-item revenue analysis (16,517 rows) | 2026-03-18 |
| ~~DL-11~~ | fact_route_skip — skipped service tracking with reasons (806 rows) | 2026-03-18 |
| ~~DL-12~~ | fact_route_move — schedule disruption tracking (3,510 rows) | 2026-03-18 |
| ~~ETL-5~~ | Nightly reconciliation — 6 raw-vs-warehouse checks, JSON report | 2026-03-26 |
| ~~IN-5~~ | Forward Cf-Access-Jwt-Assertion through Nginx to API | 2026-03-26 |
| ~~IN-6~~ | Health endpoint best-effort JWT validation — restore ETL stats in status bar | 2026-03-26 |
| ~~IN-7~~ | Ripple CF Access auth middleware — protect /api/chat LLM endpoint | 2026-03-26 |
| ~~IN-8~~ | CF-Connecting-IP for unspoofable audit log IP attribution | 2026-03-26 |
| ~~IN-2~~ | Restricted DB users — ripple_rw + metabase_ro privilege separation | 2026-03-26 |
| ~~DL-5~~ | rpt_profitability — Metabase-friendly profitability report with margin % | 2026-03-28 |
| ~~EIA-1~~ | Agent-ready YAML frontmatter on 8 glossary + 1 standard doc | 2026-03-28 |
| ~~EIA-2~~ | Enterprise index manifest (enterprise-index.yaml) | 2026-03-28 |
| ~~AQ-2~~ | SQL explanation shown as collapsible detail in query results | 2026-03-28 |
| ~~SA-C1~~ | Ripple fail_closed — reject requests if CF auth misconfigured in Docker | 2026-03-28 |
| ~~SA-H1~~ | Removed hardcoded DB passwords from init scripts | 2026-03-28 |
| ~~SA-H2~~ | Content-Security-Policy + Permissions-Policy on all nginx configs | 2026-03-28 |
| ~~SA-H3~~ | Ripple middleware ordering — auth before CORS on request path | 2026-03-28 |
| ~~SA-L1~~ | Permissions-Policy header added (camera, mic, geo, payment disabled) | 2026-03-28 |
| ~~ETL-CLERMONT~~ | Onboard CLERMONT (3rd Skimmer company) + fix post-migration pipeline | 2026-07-04 |
| ~~ETL-TRIAGE~~ | Pipeline failure triage — classify, log, Slack #alerts with impact + fix | 2026-07-06 |
| ~~IN-11~~ | Audit-log isolation → `audit` schema (MEDIUM-1) | 2026-07-14 |
| ~~IN-12~~ | Audit-log PII retention (redact @90d, delete @365d) (MEDIUM-2) | 2026-07-14 |
| ~~IN-16~~ | Rotate exposed `splashworks_ro` credential | 2026-07-14 |
| ~~IN-14~~ | Nightly ingestion report + fix chronic 24h data-lag (cron → 05:30 UTC) | 2026-07-14 |
| ~~DL-15~~ | fact_service_stop duplicate-row fix (NULL incremental key) — ~240k dup rows removed | 2026-07-15 |
| ~~IN-13~~ | Greenmill chrooted SFTP delivery + per-jail entitlements + access alerts | 2026-07-14→17 |
| ~~IN-15~~ | Status dashboard — hosted (CF Access) + Outlook-safe email report | 2026-07-17 |

---

## Size Legend

| Size | Meaning |
|------|---------|
| S | < 2 hours |
| M | 2-8 hours (half day to full day) |
| L | 1-3 days |
| XL | 3+ days (should be broken down) |
