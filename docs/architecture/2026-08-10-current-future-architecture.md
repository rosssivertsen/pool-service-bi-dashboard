# SDW & PDW — Current → Future State Architecture

**2026-08-10 · Pattern Study Phase F** · Companions: `docs/pattern-study/phase-a…e`. PDW future state is advisory only (see `pdw-advisory-briefing.md`); SDW future state is the proposed Wave 0–2 plan pending Ross's PR approval.

---

## 1. SDW — Current State

```mermaid
flowchart LR
    SK[Skimmer SaaS] -->|nightly SQLite extracts ~04:40 UTC| OD[(OneDrive)]
    OD -->|rclone 05:30 UTC| ETL[Python ETL<br/>checksums · COMPANY_MAP<br/>fingerprint seed]
    ETL --> RAW[(raw<br/>full replace, 6-mo window)]
    RAW --> DBT[dbt · 55 models]
    DBT --> STG[public_staging · 21]
    STG --> WH[public_warehouse · 18<br/>11 incremental facts]
    WH --> SEM[public_semantic · 14]
    SEM --> BIC[public_bi_compat · 2]
    SEM --> API[FastAPI<br/>NL→SQL Claude<br/>SELECT-only]
    API --> APP[React SPA]
    SEM --> MB[Metabase]
    BIC --> PBI[Power BI]
    DBT -.-> REC[8 recon checks<br/>nightly, non-gating]
    REC --> TRI[triage.py → Slack #alerts<br/>incident log · report.py email]
    PDWCI[PDW CI backups] -->|SFTP incoming/| ARC[verified archive<br/>partner-incoming/]
```

**Spine (keep):** dbt + PR + branch-per-stream · triage→Slack alerting · audit-schema isolation + PII retention · CF Access everywhere · registry-driven onboarding (COMPANY_MAP) · partner SFTP custody chain.

**Gaps (fix):** zero dbt tests, nothing gates a merge · no dimension history (SCD0 rebuild + 6-mo window = silent erasure) · no identity above (id, company) · no feed registry · semantics unversioned · no UI freshness signal.

## 2. SDW — Future State (Waves 0–2)

```mermaid
flowchart LR
    SK[Skimmer SaaS] --> OD[(OneDrive)]
    OD --> ETL[Python ETL<br/>+ per-company isolation W2<br/>+ read watchdog W2]
    ETL --> RAW[(raw)]
    RAW --> DBT[dbt]
    DBT --> SNAP[[snapshots SCD2 · W0<br/>dim_customer · location rate · routes]]
    DBT --> STG[staging]
    STG --> IDL[[identity ledger · W1<br/>customer_alias · member_exclusion]]
    IDL --> WH[warehouse]
    SEEDS[[governed seeds · W1<br/>defined_terms · tag_catalog · entity_registry]] --> WH
    WH --> COH[[dim_customer_cohort · W1]]
    WH --> SEM[semantic] --> BIC[bi_compat]
    SEM --> API[FastAPI] --> APP[React + freshness badge · W0]
    SEM --> MB[Metabase]
    FREG[[feed_registry · W0<br/>tolerances + active hours<br/>unregistered-feed detection]] -.-> REC[recon + RC-9 partner-ledger check]
    GOLD[[golden invariant suite · W1<br/>CI gate on staging + nightly prod]] -.gates.-> DBT
    TESTS[[dbt schema tests · W0]] -.gates.-> DBT
    REC --> TRI[triage → Slack]
```

**Delta summary:** the assertion layer arrives (tests W0, invariants W1, tie-outs inside golden scope), history stops being destroyed (snapshots W0 — the clock item), identity + semantics become governed data (W1 chain: ledger → seeds → cohort dim), monitoring becomes complete (feed registry W0, gates all new sources), and the serving layer becomes honest (freshness badge W0). ETL-9 (full schema governance, L) lands after, consuming DL-21/22 as down-payments.

## 3. PDW — Current State (observed, read-only)

```mermaid
flowchart LR
    SKAPI[Skimmer API] -->|hourly| SYNC[GitHub Actions sync jobs<br/>per-brand matrix, watchdog]
    QBO[QBO / Intuit] --> SYNC
    SAM[Samsara · Xima · Azuga] --> SYNC
    PGC[pg_cron dispatches workflows] -.-> SYNC
    SYNC --> LAND[(landing.*<br/>+ sync_run ledger)]
    LAND --> XW[crosswalk_guard<br/>deterministic auto-link<br/>+ human review queue]
    XW --> CM[core.* Master-ID layer<br/>registry · alias · exclusions<br/>defined_terms · 197 loose SQL]
    CM --> SERV[console/exec/hub/map/admin<br/>5 Netlify apps + warehouse_asof]
    CM -.-> GUARDS[feed_registry · freshness<br/>tie guards · golden CI]
    CM --> WBQ[change_queue] -->|password re-proof<br/>echo-PUT tags only| SKAPI
    CM --> BK[warehouse_backup.py<br/>irreplaceability-scoped] -->|SFTP| SDW[SDW archive]
```

**Keep:** the entire assertion/governance layer · identity machinery · ingestion robustness · irreplaceability-scoped backup.
**Gaps:** no migrations/environments (197 hand-applied files, documented drift) · guards page nobody · mgmt-token as routine SQL path + creds custody · monolithic canonical view vs their own BLUEPRINT layering · locked ledger without read-back (1,272-row drift).

## 4. PDW — Future State (advisory)

```mermaid
flowchart LR
    SRC[Sources] --> SYNC[Sync jobs<br/>scoped service role, vaulted creds]
    SYNC --> MIG[[migrations flow<br/>freeze SQL dir · db diff/push<br/>golden suite as gate]]
    MIG --> LAND[(landing)] --> XW[crosswalk] --> CM[Master-ID core<br/>decomposed per BLUEPRINT 4-layer]
    CM --> SERV[apps]
    CM --> RB[[ledger read-back check<br/>vs live Skimmer tags]]
    GUARDS[guards + golden] --> AL[[webhook alerting<br/>guard-log insert → Slack/Teams]]
    CM --> BK[backup] --> DRILL[[timed restore drill<br/>from SDW archived copies]]
```

All four insertions (migrations, alerting, read-back, drill) are additive — none disturb the working assertion layer. Sequencing logic mirrors ours inverted: their cheapest high-value fix is alerting (days); their compounding one is migrations.

## 5. The exchange, one table

| Pattern | Direction | Vehicle |
|---|---|---|
| Golden invariants / tie guards | PDW → SDW | DL-22 |
| feed_registry + schedule-aware freshness | PDW → SDW | ETL-10 |
| defined_terms / charter / tag_catalog | PDW → SDW | DL-25 |
| Identity ledger (alias + exclusions) | PDW → SDW | DL-24 |
| warehouse_asof freshness stamp | PDW → SDW | DA-6 |
| SCD/episode history discipline | PDW → SDW | DL-23 |
| Per-brand isolation + watchdog | PDW → SDW | ETL-11 |
| Triage → Slack alerting | SDW → PDW | advisory #2 + code offer |
| dbt/PR/migrations discipline | SDW → PDW | advisory #1 + walkthrough |
| Custody archiving + verification | SDW → PDW | already running (their backups, our archive) |
| Ledger read-back reconciliation | both | RC-9 (ours) · advisory #4 (theirs) |

## 6. Invariants that do not change

- **PDW = Pool Deck (Sam/AQPN, Supabase) · SDW = Splashworks (Ross/CCE, this repo).** Contamination boundary: `SUPABASE_*` vs `DATABASE_URL`.
- **No PDW data is ingested into SDW models** — governance backups are held as verified files (custody), and RC-9 reads them for *reconciliation*, never for modeling.
- **AQPN org: Lex Immutabilis** — local review only; advisory changes are Sam's to make.
- **SDW stays read-only toward Skimmer** — no write-back adoption.
