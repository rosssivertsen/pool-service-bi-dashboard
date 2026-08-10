# Phase C — First-Principles Benchmark

**2026-08-10 · Both systems scored against the same rubric, not against each other.**
Scale: 0 = absent · 1 = ad hoc · 2 = partial/manual · 3 = systematic · 4 = systematic + self-verifying.
Reference frames: Kimball (dimensional modeling, conformed dims, SCD), Inmon/CIF (subject-oriented integration), DAMA-DMBOK (governance, metadata, quality), medallion/ELT norms (layering, idempotence), data-contract practice, DevOps/DataOps (CI, observability, incident learning).

| # | Dimension | Principle | SDW | PDW | Evidence (verified in Phases A/B) |
|---|---|---|---|---|---|
| 1 | Layered architecture | One-directional flow; each concept true in one place | **3** | **3** | SDW: staging→warehouse→semantic (dbt-enforced). PDW: landing→identity→core→serving (BLUEPRINT.md, convention-enforced). Both clean; SDW's is tool-enforced, PDW's is discipline-enforced |
| 2 | Dimensional modeling | Facts at declared grain; conformed dimensions | **3** | **2** | SDW: proper star, 11 incremental facts w/ composite unique_key, dim_date. PDW: entity-centric views + matviews; grain lives in view logic, not declared structures |
| 3 | Master data / identity | One ID per real-world thing across systems | **1** | **4** | SDW: per-source IDs only, joins on (id, company). PDW: Master-ID hub, crosswalk w/ deterministic auto-link + human queue, merge ledger, guard views asserting identity invariants in CI |
| 4 | History & time-variance | Warehouse remembers what sources forget (SCD, snapshots) | **1** | **3** | SDW: facts accumulate but dims rebuilt (SCD0), 6-mo window erases silently (101 merges left zero trace). PDW: episode logic, frozen rosters, append-only *_log siblings, retention snapshots |
| 5 | Semantic governance | Definitions versioned, owned, tied to implementation | **2** | **4** | SDW: rich YAML+glossary, machine-consumed by AI prompt, but unversioned/unowned/unjoinable. PDW: core.defined_terms (31 versioned rows, approved_by, rule_ref), charter provenance, LINEAGE.md verified-against-live |
| 6 | Data quality assurance | Invariants asserted, violations gate deployment | **2** | **4** | SDW: 8 recon checks nightly, non-gating; ZERO dbt tests. PDW: golden CI on push/PR/nightly (guard views empty, waterfall balances), tie guards, "broken twice = test" rule |
| 7 | Pipeline observability | Failures detected, classified, routed to humans | **4** | **2** | SDW: triage.py signature KB → incident log → Slack + recovery notices + Haiku enrichment. PDW: sync_run ledger + freshness/feed guards log richly, but no human alerting (11 failed pushes sat silent) |
| 8 | Monitoring completeness | The monitoring system knows what it should be monitoring | **1** | **4** | SDW: per-company freshness only; unmonitored feed undetectable. PDW: feed_registry w/ per-feed tolerance + unregistered-feed detection |
| 9 | Change management | Versioned, reviewable, reversible schema/logic changes | **4** | **1** | SDW: dbt + git PR + branch-per-stream + migrations + staging mirror. PDW: 197 loose date-prefixed SQL files, no migration tool, live-DB drift (mitigated only by manual verification passes) |
| 10 | Security & access | Least privilege, audit isolation, credential custody | **3** | **2** | SDW: audit schema isolation, PII retention policy, CF Access, anonymized staging, chrooted SFTP + custody archive. PDW: RLS + capability model + password re-proof on write-back (strong), but creds file in synced folder, apikey in workflow, mgmt-token SQL path |
| 11 | Ingestion robustness | Sources fail; ingestion degrades gracefully, never corrupts | **2** | **4** | SDW: checksum change-detection, loud skip of unmapped extracts; but one process for all companies (silent-starvation class risk), no watchdog story. PDW: wall-clock watchdog, CF 52x backoff class, per-brand isolation matrix, shape validation, schema-introspecting upserts |
| 12 | Provenance & lineage | Every number traceable to source + decision | **2** | **3** | SDW: checksums + etl_load_log + fingerprint seed; ETL-6/7/8 pending; decisions in git only. PDW: LINEAGE.md (verified), rule_ref chain, decided_by columns, RULINGS log; but no VCS-grade code lineage |
| 13 | Serving-layer honesty | Consumers can see currency + trust of what they read | **1** | **3** | SDW: no freshness display anywhere. PDW: warehouse_asof stamp on every page header |
| 14 | Incident → institutional learning | Failures become permanent defenses | **3** | **4** | SDW: triage signature KB grows per incident; runbooks. PDW: every incident in Phase A traced to a codified guard/test/registry with dated comment provenance |
| **Σ** | | | **32/56** | **43/56** | |

## Reading the scores honestly

- **The totals mislead if read as "PDW is better."** PDW's 43 rides on dimensions 3–8 and 11 — the assertion layer. Its two worst scores (change management 1, security 2) are the two that *destroy* systems; SDW's worst (identity 1, history 1, completeness 1) are the two that *limit* them. A warehouse with weak assertions gives wrong answers; a warehouse with weak change management eventually can't be changed at all. Different failure modes, different clocks.
- **Neither system scores 4 on the same dimension anywhere.** The complementarity measured in Phases A/B is confirmed structurally: across 14 dimensions there is no tie at the top. This is why "exchange, not ranking" is the right frame.
- **SDW's path to 4s is cheaper than PDW's.** SDW's gaps are additive (add tests, add registry, add terms table — no rework of existing structure). PDW's gaps are subtractive/structural (retrofit migrations onto 197 applied files, move creds, add alerting paths). This asymmetry matters for the recommendation sequencing in Phase E.
- **Dimension 8 (monitoring completeness) is the sleeper.** It scores lowest for SDW of anything cheap to fix, and it compounds: every future source (Samsara, Xima, QBO) inherits the gap or inherits the registry, depending on what we do first. Fix before onboarding new sources, not after.

## Rubric notes (for reuse)
- Dimensions 1–5 are Kimball/Inmon/DAMA classical; 6–9 are DataOps; 10 is CIA-triad applied; 11–14 are operational-maturity extensions that the classical literature under-weights but that Phases A/B showed decide real outcomes.
- Score 4 requires self-verification (the mechanism checks itself — e.g., feed_registry detecting unregistered feeds, golden suite gating merges). A human remembering to check caps at 3.
