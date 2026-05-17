# auto-reconcile

A minimal financial reconciliation web app. Workspace owners configure two data sources (an accounting source of invoices and a bank source of transactions), import CSVs into each, then run an exact matcher that pairs up obvious 1:1 matches and quarantines ambiguous overlaps as exceptions for human review.

The interesting part is not the CRUD — it's the matcher: how to find 1:1 matches without falsely pairing items that have multiple equally-valid candidates, and how to do that safely when concurrent runs touch overlapping rows.

## Stack

- **Rails 8.1** on **Ruby 3.4.9** (managed by `mise`)
- **PostgreSQL 17** with a 4-database topology in production (primary + cache + queue + cable)
- **SolidQueue** for background jobs, **Solid Cache**, **Solid Cable** — all DB-backed, no Redis
- **Hotwire** (Turbo + Stimulus), **importmap-rails** (no Node toolchain), **Tailwind** via cssbundling
- **Active Storage** for uploaded CSVs

## The reconciliation problem

Given a list of accounting invoices and a list of bank transactions over the same period, the naive approach — "pair anything with the same amount" — quietly breaks the moment two invoices share a value, or one invoice gets paid by two transactions, or a customer pays the wrong amount. A useful reconciler has to recognize:

- **Exact 1:1 matches** with high confidence (auto-confirm-eligible).
- **Ambiguity groups** — sets of items where multiple pairings are equally plausible. These can't be auto-resolved without losing information, so they're surfaced as exceptions with the full overlap context attached.
- **Unmatched items** — items with no candidate at all (likely missing data from the other side, timing differences, or genuine errors).

This v1 implements the deterministic exact matcher. Fuzzy matching (amount tolerances, payer-name similarity) and LLM-assisted exception explanations are roadmap items.

## Architecture

### Data model

```
Workspace ──┬── DataSource (kind: accounting | bank)
            │     └── ImportBatch ── ReconcilableItem ──delegated_type──► Invoice | BankTransaction
            │                                                                   │
            └── ReconciliationRun                                                │
                  ├── Match ── MatchLeg ──────────────────────────────────────► (side: a | b)
                  └── ReconciliationException ─────────────────────────────────► (category: duplicate, ...)
```

Notes:
- **`ReconcilableItem`** is the unified matching surface. It uses Rails' `delegated_type` to point at either an `Invoice` or a `BankTransaction`, so the matcher can join/filter purely on `(amount_cents, amount_currency, occurred_on, status)` without caring about the underlying record type. New source types (e.g., Stripe payouts) become "just another delegated type" without touching the matcher.
- **`Workspace`** is the tenancy boundary. Every domain table carries `workspace_id` with a FK and a partial index, and every query in controllers/services is scoped through `current_workspace.data_sources` (etc.) so a missing scope can't silently leak rows across tenants.
- **`MatchLeg`** is a join table with a `side` column rather than a `match.invoice_id` + `match.bank_transaction_id` pair. This generalizes to 1:N or N:M matches (split invoices, batched payments) without a schema change.
- Money is stored as `bigint amount_cents` + `string amount_currency` (via `money-rails`). No floating-point currency anywhere.
- Soft deletion via `discard` on every long-lived row, so a deleted source doesn't break audit trails on past runs.

### Matching algorithm

In [`app/services/matchers/exact_matcher.rb`](app/services/matchers/exact_matcher.rb).

**Step 1 — Candidate edges.** For each unmatched invoice in the run's date window, query for bank transactions in the same workspace with: same amount, same currency, posted within `[invoice_date, invoice_date + 7 days]`. Each match is an edge `(invoice_id, bank_txn_id)` in a bipartite graph.

**Step 2 — Connected components via BFS.** Build an adjacency map from the edges, then BFS over it. Each connected component is a self-contained "ambiguity unit" — items in different components can never affect each other's pairing decision.

**Step 3 — Per-component verdict.**
- Component shape is exactly `{1 invoice, 1 bank txn}` → **commit as a `Match`** with two `MatchLeg`s (sides a/b), both items moved from `unmatched` to `proposed`.
- Any other shape (1:N, N:1, N:M) → **commit as an ambiguity group**: every involved item becomes a `ReconciliationException` with `category: "duplicate"` and a jsonb `metadata` blob containing the shared `group_key`, the human-readable reason, and the full lists of involved item IDs split by side. The matcher deliberately does not guess — exceptions hold all the information a reviewer needs to resolve manually.

**Concurrency safety.** Each component is processed in its own transaction. The involved items are locked with `SELECT FOR UPDATE` in **ascending id order** (deadlock-safe — any two concurrent transactions touching overlapping rows will acquire locks in the same order). Status is re-checked under the lock; if another worker has already moved one of the items out of `unmatched`, the component is skipped rather than overwritten.

**Fail-fast guards.** [`validate_run!`](app/services/matchers/exact_matcher.rb#L69) raises `ArgumentError` if the run is misconfigured (same source on both sides, cross-workspace source, wrong `kind`). These are programmer/operator bugs, not data anomalies — silently producing empty results would mask the real problem. The controller mirrors the same kind/workspace constraints in `find_by` so direct POSTs that bypass the form's filtered dropdowns are rejected before any job is enqueued (defence in depth).

### Background job pipeline

Two jobs, both via SolidQueue:

- **`ImportBatchJob`** — parses an uploaded CSV row-by-row, normalizes sign and currency, creates `Invoice` / `BankTransaction` records plus a `ReconcilableItem` wrapper for each. Idempotency is enforced by a unique index on `(data_source_id, external_id_hash)` — re-importing the same CSV increments `duplicate_count` instead of producing dupes. Two importer strategies are dispatched on the source's `schema_mapping`: `FixedCsv` (canonical headers) and `MappedCsv` (header remapping for arbitrary bank exports).
- **`ReconciliationRunJob`** — thin lifecycle wrapper around `ExactMatcher`: owns status transitions (`queued` → `running` → `complete` / `failed`), timing, jsonb `stats` persistence, and error capture. The matcher itself stays a pure service that takes a run and returns a stats hash. On retry, the lifecycle fields are cleared but item-level status changes from a prior partial run are not rolled back — those items simply get excluded from the next run's candidate set, which is the conservative thing to do under "matcher already partially committed real changes."

### Multi-tenancy

There's no auth in v1 (`current_workspace = Workspace.first!`, `current_user = User.first!`), but the data model is built for it: every domain table has a `workspace_id` FK, every controller scopes through `current_workspace`, and the matcher refuses to run if either source's `workspace_id` doesn't match the run. The path to real multi-tenant auth is "replace `Workspace.first!` with a session-backed lookup" — no model changes required.

## Testing

Four tiers, run with `bin/rails test`:

| Layer | Location | What it covers |
| --- | --- | --- |
| Model | `test/models/` | Validations, scopes, associations, custom methods. One file per model. |
| Service | `test/services/matchers/`, `test/services/importers/` | Algorithm correctness with hand-built fixtures: matched-1:1, ambiguity-1:N, ambiguity-N:M, cross-currency rejection, out-of-window rejection, sign normalization, idempotent re-import. |
| Job | `test/jobs/` | Lifecycle wrapping: status transitions on success/failure, stats persistence, retry resets, error message capture. |
| Controller | `test/controllers/` | Request-level integration: form rendering, valid + invalid POST paths (missing source, end-before-start, wrong-kind source, cross-workspace source), 404 for cross-workspace show, redirect targets. ActiveJob runs in `:test` mode so `assert_enqueued_jobs` verifies the job-handoff contract. |

Total: **71 tests, 371 assertions**, ~1s wall clock.

## Local setup

Requires Ruby 3.4.9 (via `mise`) and PostgreSQL 17 running locally.

```bash
mise install                 # Ruby 3.4.9
bundle install
bin/rails db:prepare         # creates all 4 dev DBs and runs migrations
bin/rails db:seed            # 1 workspace, 1 user, 2 demo data sources (idempotent)
bin/dev                      # boots web + tailwind watcher + SolidQueue worker via foreman
```

App runs at <http://localhost:3000>.

## Three-step user flow

The happy path is intentionally sequential — each step is its own page so the user model stays obvious:

1. **Configure a data source** (`/data_sources`) — name, kind (accounting | bank), currency. Seeded by `db:seed` with one of each, so you can skip this for the demo.
2. **Import a CSV into a source** (`/import_batches/new`) — sample CSVs at `tmp/demo_invoices.csv` and `tmp/demo_bank.csv` reproduce the canonical end-to-end output (1 exact match + 1 ambiguity group of 3 + 1 unmatched invoice).
3. **Run reconciliation** (`/reconciliation_runs/new`) — pick the two sources and a date range. The background job runs `ExactMatcher`; the run's show page auto-refreshes while `queued` / `running` and then renders the matches, exceptions, and per-side counter stats.

## Out of scope for v1 (deliberate)

These are explicit cuts to keep the v1 surface honest about what's been built and what hasn't:

- **Auth** — single-tenant runtime via `Workspace.first!` / `User.first!`. The data model is already multi-tenant; adding session-backed auth is a controller-layer change.
- **Fuzzy matching** — no amount tolerance, no payer-name fuzzy match, no date-window tuning per source. All three are roadmap items but each introduces calibration questions (false-positive rate, per-tenant thresholds) better answered with real customer data.
- **LLM explanations** — `ReconciliationException` has an `llm_explanation` text column already so the schema is ready; the integration itself is intentionally deferred.
- **Exception resolution UI** — exceptions render but can't yet be resolved through the web UI. Resolution columns (`resolved_at`, `resolved_by_user_id`, `resolution`) exist on the table.
- **Real-time updates** — the run's show page auto-refreshes via an HTML meta refresh rather than Turbo Streams. Cheap, ugly, works.
