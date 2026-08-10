# PDW Advisory — Briefing for the Holdco Conversation

**For:** Ross (to deliver to Sam / AQPN Holdco as he judges fit) · **Date:** 2026-08-10
**Basis:** Read-only review of a local `warehouse-sync` clone (@ `9447754`, 2026-08-09) + the governance backups PDW's CI delivers to our SFTP. Nothing in the AQPN org was touched. These are general recommendations about PDW, packaged as talking points — the framing, order, and which items to raise are your call.

## Open with credit (it's earned, and it buys the rest of the conversation)

Five PDW mechanisms are better than most production data teams ship, and SDW is adopting them:

1. **`core.defined_terms`** — versioned business definitions with approver + rule_ref, born from a signed-off charter
2. **Golden suite** — structural invariants gating every push; "broken twice = test"
3. **`core.feed_registry`** — unmonitored feeds are structurally impossible; unregistered *success* is itself a warning
4. **Schedule-aware freshness guard** — solved a false-alarm problem we had open on our own board, better than either fix we were weighing
5. **Identity layer** — deterministic-only auto-linking + human review queue + merge ledgers + CI guard views; textbook MDM, pragmatically executed

Leading with "we're copying five of your things" makes the rest land as peer exchange, not audit.

## The recommendations (your worry-order, with talking points)

### 1. Change management — the one that gets worse on its own
- **Finding:** 197 hand-applied SQL files, no migration tool, no staging environment; repo↔live drift is documented by PDW's own `_live_20260807/` snapshot dir and a flagged drift in their LINEAGE.md. Every change is effectively tested in production.
- **Recommendation:** Incremental migration adoption — freeze the SQL dir as history, route new changes through `supabase db diff`/`db push`, let the golden suite gate it. Key reframe for the conversation: **the golden suite already solved the scary half of a migrations rollout** — the safety net exists, only the delivery mechanism is missing.
- **Offer:** a dbt/migrations walkthrough of our setup, an afternoon.

### 2. Alerting — guards that fire with nobody paged
- **Finding:** Freshness guard, tie guards, golden suite all *record* findings; none *page* a human. Measured consequence: 11 failed Skimmer pushes sitting silent in the change queue (2026-08-09). A guard that logs without paging is a smoke detector with the battery in a drawer.
- **Recommendation:** One webhook from guard-log inserts + workflow failures to Slack/Teams. Days of work.
- **Offer:** our triage pattern (signature KB → classified incident → alert → recovery notice) as pattern or code — it's client-agnostic.

### 3. Credential custody — inconsistent with PDW's own rigor
- **Finding:** Reader creds in a synced cloud folder; a publishable apikey committed in a workflow; the Supabase **management token** (whole-account credential) as the routine SQL path.
- **Recommendation:** Accelerate their own Phase 3 vault plan; scoped service role for routine syncs so one leak ≠ whole account.
- **Delivery note:** this is the touchiest item — it lands better as "your Phase 3 plan is right, pull it forward" than as a new finding.

### 4. The acquisition ledger has drifted from Skimmer
- **Finding:** `core.customer_acquisition` fully locked (6,454 rows) while Skimmer tags kept moving: **1,272 rows of one-directional drift** measured 2026-08-09, including three cohorts (Revitalize, SoClean, PHXHS) in the entity registry that never entered the ledger. Locking without read-back = a system of record that becomes confidently wrong.
- **Recommendation:** one scheduled ledger-vs-live-tags comparison.
- **Offer:** we're building the same check on our side from the backups we hold (RC-9); we can share the diff output.

### 5. A backup is proven by a restore
- **Finding:** Backup design is excellent (irreplaceability-scoped, manifested, SHA-256 — every delivery to us has verified clean). No evidence of a restore drill; the runbook exists but appears unexercised.
- **Recommendation:** one timed drill into a scratch Supabase project.
- **Offer:** our root-owned archived copies as the drill source — their execution, our bytes.

### 6. Smaller items (raise opportunistically)
- String sentinels (`'ACTIVE'`, `'NA'`) in entity_registry — we were burned by this exact class (Skimmer's noon sentinel); typed NULLs/dates are cheap insurance
- The 267-line canonical view does episodes + rates + precedence + exclusions in one object; **their own BLUEPRINT.md is the decomposition map** — frame as "your target doc is ahead of your implementation, which is the right order of problems"
- Manifest docs say SHA-256 (correct); early comms said MD5 — align the docs so nobody verifies against the wrong algorithm

## Standing offers (summarized for the close)

1. Triage/alerting pattern or code · 2. Restore-drill source data · 3. Ledger-drift diff reports · 4. Migrations walkthrough

## What NOT to bring up
- Rubric scores or "SDW vs PDW" totals — invites ranking, poisons exchange
- Anything implying we monitored their production — everything above came from their repo (which they shared org access to) and the backups they deliver to us
