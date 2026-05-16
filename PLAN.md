# Auto-Reconcile — Plan

AI-powered financial reconciliation app. Matches records from two sources
(bank ↔ invoice in v1) to find pairs, flag mismatches, explain discrepancies.

## Stack

- Rails 8.1 (Ruby 3.4.9, managed via `mise`)
- PostgreSQL 17
- Tailwind CSS (vanilla, no component library)
- Hotwire (Turbo + Stimulus), importmap
- SolidQueue (background jobs), SolidCache, SolidCable
- Active Storage (file uploads)
- `money-rails` (Money objects, `monetize`)
- `discard` (soft delete, opt-in scope)
- Devise / Rails 8 built-in auth — phase 1b
- `anthropic` gem (LLM) — phase 1d

## Phasing

### Phase 1a — minimum spine (current)

Bank CSV ↔ invoice CSV exact-match reconciliation. Single hardcoded
workspace. User+Membership models exist but no real auth yet (no password
fields). Several models have user FK references prepared for 1b.

Build order:
1. Rails new + gem setup ✓
2. money-rails + discard ✓
3. 13 migrations + Active Storage migrate ✓
4. Model wiring: associations, validations, enums, Discard, monetize,
   delegated_type ✓
5. Seed: 1 user, 1 workspace, 1 membership, 2 data sources ✓
6. Importers: `Importers::Base` + `Importers::FixedCsv` +
   `Importers::MappedCsv`, `ImportBatchJob`
   - **`Importers::Base` owns the lifecycle** (Template Method): sets
     `started_at` / `completed_at`, flips `status`
     `queued → processing → complete/failed`, increments
     `processed_count` / `success_count` / `error_count` /
     `duplicate_count`, appends to `error_log`. Subclasses override
     only `iter_rows(batch)` and `import_row(batch, row, row_number)`.
   - **`error_log` shape is fixed** — array of row-level hashes:
     `[{ row_number:, external_id:, error:, raw_row: }, ...]`. Same
     shape across all importers so the UI / debugging doesn't branch.
   - **Duplicates are expected, not errors.** Rescue
     `ActiveRecord::RecordNotUnique` from the
     `(data_source_id, external_id_hash)` index, increment
     `duplicate_count`, continue. DB constraint stays the final
     authority; `error_log` only collects real errors.
   - **Idempotent on retry.** SolidQueue may re-run `ImportBatchJob`.
     Policy: re-process every row; the unique index turns previously
     imported rows into `duplicate_count++`. No resume cursor, no
     wipe-and-reimport.
   - **Importer owns the kind → subtype mapping**, not the job.
     `Importers::FixedCsv` reads `batch.data_source.kind` and picks
     `BankTransaction` vs `Invoice`. `ImportBatchJob` only chooses the
     strategy.
   - **Importer family in v1a**:
     - `Importers::FixedCsv` — assumes canonical column names
       (`external_id`, `posted_date`, `amount`, `txn_type`, ...).
       Used when `data_source.schema_mapping` is empty.
     - `Importers::MappedCsv` — reads
       `data_source.schema_mapping` (jsonb) to translate raw CSV
       column names into canonical ones, then delegates to the same
       row-handling code as `FixedCsv`. Used when mapping is present.
     - `Importers::LlmInferred` (phase 1d) — calls Claude once per
       DataSource to populate `schema_mapping`, after which
       `MappedCsv` handles future imports for that source. Schema
       doesn't change.
     - `ImportBatchJob#importer_for` dispatches on
       `data_source.schema_mapping.present?` (Strategy pattern).
   - **Real bank CSVs come in 3 shapes**; v1 covers the first two
     via the importer family:
     - **Format B — positive amount + `txn_type` column** (Xero,
       QuickBooks). `FixedCsv` canonical. Sign applied via
       sign-convention rule above.
     - **Format A — signed amount, no `txn_type` column** (Stripe
       payouts, many AU banks). Handled by `MappedCsv` —
       `schema_mapping` omits the `txn_type` key, importer reads
       amount as-is and reverse-derives `BankTransaction.txn_type`
       from the sign.
     - **Format C — separate debit/credit columns** (Chase, BoA).
       Not in v1; needs `LlmInferred` (phase 1d) because column
       names vary per bank ("Debit Amount" vs "Withdrawal" vs
       "Money Out").
   - **Sign convention on `ReconcilableItem.amount_cents`**:
     positive = money in (invoices, bank credits); negative = money
     out (bank debits). Applied at import time so the matcher can
     compare `amount_cents` directly without ever touching
     `BankTransaction.txn_type`. Subtype-agnostic, directionality
     free. `BankTransaction.txn_type` is still stored as a human
     label for UI/display.
   - **Sign authority per importer (precise contract):**
     - **`FixedCsv` (Format B)** — `amount` column is expected
       positive/absolute; `txn_type` column is authoritative.
       Importer defensively normalizes:
       ```
       amount_cents = amount_cents.abs
       amount_cents = -amount_cents if txn_type == "debit"
       ```
       This means even if a user supplies a signed value with
       `txn_type=debit, amount=-100`, the result is unambiguously
       `-100` (not flipped twice to `+100`). The `.abs` line is a
       safety net against bad input; the `txn_type` line is the
       semantic truth.
     - **`MappedCsv` (Format A)** — `amount` is signed and
       authoritative; `txn_type` column is absent. Importer reads
       `amount_cents` as-is (no `.abs`), then reverse-derives
       `BankTransaction.txn_type` for display:
       ```
       txn_type = amount_cents >= 0 ? "credit" : "debit"
       ```
       If a Format A `schema_mapping` accidentally includes a
       `txn_type` mapping, importer prefers `txn_type` over sign
       (matches `FixedCsv` semantics) — but this combination
       shouldn't happen in practice; documented in importer test.
     - **Invoices** (any importer) — always positive; no sign
       handling needed. Invoice without an amount is a validation
       error, not an import.
   - **Watch:** `Invoice.invoice_number` is unique per workspace, but
     the `ReconcilableItem` dedupe key is per data_source. Two
     accounting sources in the same workspace with the same invoice
     number will collide on the invoice constraint even though the
     dedupe keys differ. Acceptable in v1a (single accounting source);
     revisit if/when a second one appears.
7. Matchers: `Matchers::ExactMatcher`, `ReconciliationRunJob`
   - **Prerequisite migration** (lands in v1a, after the
     `schema-v1` PR): `add_column :reconciliation_exceptions,
     :metadata, :jsonb, default: {}, null: false`. Required by the
     ambiguity path (see "Exact matcher (v1a) — design" below).
     No GIN index in v1a — add only when a query pattern needs it.
   (see "Exact matcher (v1a) — design" below)
8. Controllers, routes, Hotwire views
   - `DataSourcesController#edit/update` — JSON textarea to set
     `schema_mapping` (interactive wizard deferred to v1.1, see
     "Importer family" above)
     - **Mandatory `schema_mapping` parse + validate in `update`**:
       textarea posts a String; controller must `JSON.parse` it,
       `rescue JSON::ParserError` → re-render `edit` with flash, and
       assert the result `is_a?(Hash)` before assignment. Without
       this, an empty/invalid string lands in the jsonb column as
       `""` or `nil` and breaks `ImportBatchJob#importer_for`
       dispatch (`"".present?` is `false` ✓ but `"{}".present?` is
       `true` ✗ — a stringified JSON would route to `MappedCsv`
       and crash on `mapping[key]`).
     - **Belt-and-suspenders model validation**: `DataSource`
       validates `schema_mapping.is_a?(Hash)` so direct Console
       writes / seeds / fixtures can't bypass the controller.
       Defense-in-depth — the controller is the user-facing guard,
       the model is the system-of-record guard.
   - `ImportBatchesController#new/create/show` — file upload, status
     and counters page
   - `ReconciliationRunsController#new/create/show` — pick source_a /
     source_b / date range, list matches and exceptions
   - **UI scope discipline for v1a** (deliberate non-goals):
     - Plain ERB + Tailwind utility classes inline — no partial
       abstraction, no component library, no daisyUI/Flowbite
     - No custom Stimulus controllers — Turbo's default link/form
       interception is enough for SPA-feel
     - No Turbo Stream broadcasts (e.g., live import progress) —
       page refresh on `show` is fine; broadcast would be feature
       creep for 1-week sprint
     - Desktop layout only, no responsive/mobile work
     - One `application.html.erb` with a top nav bar
       (Imports / Runs / Data Sources), 3 page templates
9. Sample CSV fixtures (one valid, one with header whitespace, one
   with duplicate rows for retry demo, one in Format A to exercise
   `MappedCsv`)
10. End-to-end manual test (upload → import → run → matches)

#### Exact matcher (v1a) — design

`Matchers::ExactMatcher.new(reconciliation_run).call` (symmetric API
to `Importers::Base.new(batch).call`). Operates on parent
`ReconcilableItem` fields only — never touches `BankTransaction` or
`Invoice` directly (delegated_type win).

**Preconditions (raise if violated):**
- `run.source_a.kind == "accounting"` (invoice side)
- `run.source_b.kind == "bank"` (bank side)
- `run.source_a.workspace_id == run.workspace_id` and same for source_b
- `run.source_a_id != run.source_b_id`

v1 does not auto-detect direction — caller passes invoice as A, bank
as B.

**Candidate filter (a ↔ b):**
- `a.data_source_id == run.source_a_id` and `b.data_source_id == run.source_b_id`
- `a.status == "unmatched"` and `b.status == "unmatched"`
- `a.amount_cents == b.amount_cents` (sign-bearing — see sign
  convention above)
- `a.amount_currency == b.amount_currency` (same currency; FX deferred)
- `a.occurred_on` in `run.date_range_start..run.date_range_end`
  (invoice strictly inside window)
- `b.occurred_on >= a.occurred_on` AND
  `b.occurred_on <= a.occurred_on + 7.days` (bank may be same day
  or up to 7 days *after* invoice — one-directional tolerance)
- Bank candidate pool extends to `run.date_range_end + 7.days` so
  month-end invoices can match early-next-month bank entries

`DATE_TOLERANCE_DAYS = 7` is hardcoded in v1; later moves to
`Workspace.settings`.

**Bidirectional uniqueness:**
For each tentative pair (a, b):
- Compute a's bank candidates → must be `[b]`
- Compute b's invoice candidates → must be `[a]`

Only commit a match if both sides are uniquely paired. Otherwise it's
ambiguous → exception path (see below).

**Commit path (transactional, with row locks):**
```
ReconcilableItem.transaction do
  a = ReconcilableItem.lock.find(a.id)   # SELECT ... FOR UPDATE
  b = ReconcilableItem.lock.find(b.id)   # SELECT ... FOR UPDATE
  return unless a.status == "unmatched" && b.status == "unmatched"
  Match.create!(reconciliation_run:, workspace:, method: "exact",
                status: "proposed", confidence: 1.0,
                reasoning: "Exact match: ...")
  MatchLeg.create!(match:, reconcilable_item: a, side: "a",
                   allocated_amount_cents: a.amount_cents,
                   allocated_currency: a.amount_currency)
  MatchLeg.create!(match:, reconcilable_item: b, side: "b",
                   allocated_amount_cents: b.amount_cents,
                   allocated_currency: b.amount_currency)
  a.update!(status: "proposed")
  b.update!(status: "proposed")
end
```

`Match.status = "proposed"` — never `"confirmed"` automatically.
Human confirmation lives in phase 1c+.

**Concurrency model**: `.lock.find` issues `SELECT ... FOR UPDATE`,
which takes a **transaction-scoped row lock** on each `ReconcilableItem`.
Properties:
- Row-level (not table) — only the two specific items are locked
- Held by the transaction; auto-released on `COMMIT` / `ROLLBACK`
- Blocks other `SELECT FOR UPDATE` / `UPDATE` / `DELETE` on the
  same row; does NOT block plain `SELECT` (Postgres MVCC)
- Crash-safe — if the worker dies mid-transaction, PG aborts and
  releases the lock; no manual cleanup
- Status recheck after the lock catches the case where another
  worker already moved the item to `proposed` while we were waiting
  on the lock

**Lock ordering to avoid deadlock**: when locking multiple rows
(both the 2-row commit path and the N-row ambiguity path), always
acquire locks in ascending `id` order. The commit path orders
implicitly (invoice `a` always has lower id than its bank candidate
since `a` was created first in seed/import; if that invariant
weakens, sort explicitly). The ambiguity path **must** sort the
group members by id before iterating — without this, two workers
hitting overlapping groups could deadlock.

A partial unique index on `match_legs(reconcilable_item_id)`
filtered by non-rejected matches is a **defense-in-depth** option
for phase 1c+ — belt to the FOR UPDATE suspenders. Not required
for v1a correctness.

**Ambiguity path (multiple candidates on either side):**
- Build the full ambiguity group across both sides
- Do NOT create a Match
- Enter `ReconcilableItem.transaction`; lock every group member
  with `.lock.find(id)` **in ascending `id` order** (deadlock
  avoidance — see "Lock ordering" above)
- Re-check that each locked item is still `status == "unmatched"`;
  skip the whole group if any item already moved (another worker
  beat us to it)
- For *every* item in the group (both sides):
  - `item.update!(status: "exception")`
  - Create `ReconciliationException(category: "duplicate")` with
    metadata jsonb:
    ```json
    {
      "group_key": "<uuid>",
      "involved_reconcilable_item_ids": [1,2,3,4],
      "source_a_item_ids": [1,2],
      "source_b_item_ids": [3,4],
      "reason": "multiple_a_for_one_b" |
                "multiple_b_for_one_a" |
                "many_to_many"
    }
    ```
- `group_key` is `SecureRandom.uuid` per ambiguity event; correlates
  exceptions in the UI ("show others in this group")

The unique index `(reconciliation_run_id, reconcilable_item_id)` on
`reconciliation_exceptions` prevents duplicate exception rows within
a single run. Cross-run duplicates are correct (each run is an audit
snapshot); since exception items are skipped by `status` filter,
subsequent runs won't re-flag them unless a user manually resets
status to `unmatched`.

**`ReconciliationRun.stats` (jsonb) populated by the matcher:**
```json
{
  "candidates_evaluated": 247,
  "matches_created": 12,
  "exceptions_created": 3,
  "source_a_in_window": 50,
  "source_a_unmatched": 32
}
```

Field definitions (all counts measured **after** matcher finishes):
- `candidates_evaluated` — total (a, b) pairs the matcher
  considered (rough cost metric; useful for spotting performance
  regressions as data grows)
- `matches_created` — `Match` rows created this run (excludes
  matches from prior runs)
- `exceptions_created` — `ReconciliationException` rows created
  this run
- `source_a_in_window` — total `ReconcilableItem`s from
  `run.source_a` (invoices) where
  `occurred_on ∈ [date_range_start, date_range_end]`. This is the
  **denominator** for "how complete is the reconciliation".
  Captured at matcher start (snapshot) so the % reconciled can be
  computed as `(matches_created + exceptions_created) /
  source_a_in_window`.
- `source_a_unmatched` — invoices in `source_a_in_window` that
  remain `status == "unmatched"` after the matcher runs (no
  candidate found, not ambiguous). This is the user's "what's left
  to investigate" number.

**Why invoice-side framing**: a reconciliation run answers "did my
invoices get paid?" — the invoice side is the question, the bank side
is the data source we search against. Bank entries with no matching
invoice (interest, fees, refunds) are *expected* to stay unmatched
and aren't a quality signal. v1 deliberately does not report
`source_b_unmatched` to avoid implying it's a defect.

**Run lifecycle (`queued → running → complete/failed`)** is owned by
`ReconciliationRunJob` (the thin wrapper), not the matcher. Matcher
is pure logic. Same split as `ImportBatchJob` + `Importers::Base`.

**Known v1 limitations** (called out in README, not hidden):
- Date tolerance hardcoded at 7 days
- Caller must pass invoice as A, bank as B (no auto-detect)
- One bank source ↔ one accounting source per run (no fan-in)

**Multi-worker safe** via row-level `SELECT FOR UPDATE` on
`reconcilable_items` inside the matcher transaction (see
"Concurrency model" above). Lock ordering is deterministic
(ascending `id`) to prevent deadlock.

### Phase 1b — auth

Add password fields to existing users table via `add_column` migration
(Devise or Rails 8 `bin/rails generate authentication`). Add Pundit
scoping. Real login flow.

### Phase 1c — Rule engine

Add `Rule` model. User-authored patterns sit between exact-match and the
(future) LLM tier in the pipeline. Admin UI to create/edit rules.

### Phase 1d — Payment subtype + LLM adjudication

Add `Payment` as a third `ReconcilableItem` subtype. Add
`Matchers::LlmMatcher` — sends ambiguous candidate sets to Claude with
structured output, populates `Match.reasoning` and
`ReconciliationException.llm_explanation`. Also adds
`Importers::LlmInferred` which populates `DataSource.schema_mapping`
from CSV header + sample rows (handles Format C and unknown variants).

**Why LLM is deferred, not half-built in v1a:**
- Exact matcher covers >80% of real reconciliation traffic; LLM is
  the long-tail differentiator
- LLM integration is its own substantial scope: API key management,
  structured output schemas, prompt design, rate limit / retry /
  timeout handling, test strategy (recorded fixtures via VCR — can't
  hit the API in CI)
- A half-built LLM matcher looks worse than a well-designed deferred
  one. "Designed, not implemented" with a concrete API sketch (see
  `Matchers::LlmMatcher` placeholder in `Match.method` enum) shows
  judgment; partial code shows urgency without judgment.
- `ReconciliationException.metadata` jsonb + `Match.reasoning` text
  columns are already in v1a schema as the landing spots for LLM
  output — no schema migration needed when 1d arrives.

## Matching pipeline (tiered, cheapest-first)

1. **Exact match** — same amount, same currency, invoice in run
   window, bank same day or up to 7 days after invoice; both sides
   must be uniquely paired (see "Exact matcher (v1a) — design").
2. **Rule match** — user-authored patterns (phase 1c).
3. **LLM adjudication** — Claude with structured output for ambiguous
   candidates (phase 1d).
4. **Human review** — anything below confidence threshold goes to a
   review queue. Confirmations could later train rules (deferred).

## Testing strategy (v1a)

Different test types map to different risks. v1a deliberately covers
three tiers so the test pyramid is visible to reviewers:

- **Unit tests** — pure logic, fast, comprehensive
  - `test/services/importers/base_test.rb` — lifecycle, counters,
    error_log shape, duplicate handling, idempotent retry. Uses
    in-test `StubImporter` subclass so `Base` is tested in isolation
    without depending on `FixedCsv` semantics.
  - `test/services/importers/fixed_csv_test.rb` — CSV parsing,
    kind routing, `to_cents` edge cases (`$1,234.56`, `2,000`),
    sign convention (debit → negative), header normalization, retry
    becomes duplicates.
  - `test/services/importers/mapped_csv_test.rb` — column
    translation via `schema_mapping`, Format A (signed amount, no
    txn_type → reverse-derive), missing-key handling.
  - `test/services/matchers/exact_matcher_test.rb` — happy path,
    date tolerance edges (0 / 7 / 8 days, before invoice), source
    kind preconditions raise, single-side uniqueness fails ambiguity
    check, both-side ambiguity, multi-currency rejected, run-window
    boundaries, idempotent re-run, exception metadata structure.
- **Request tests** — controller wiring + HTTP layer
  - `test/controllers/reconciliation_runs_controller_test.rb` —
    `POST /reconciliation_runs` enqueues `ReconciliationRunJob`,
    `GET /reconciliation_runs/:id` renders matches + exceptions.
- **Integration tests** — full vertical slice
  - `test/integration/import_and_reconcile_flow_test.rb` — upload
    CSV via Active Storage → run `ImportBatchJob` synchronously →
    create `ReconciliationRun` → run `ReconciliationRunJob`
    synchronously → assert match counts, exception counts, and
    `ReconcilableItem` status transitions across the whole pipeline.

**Deliberate non-goals for v1a testing:**
- No system tests (Capybara / Selenium). Integration test already
  exercises the wiring; system test ROI is low in a 1-week sprint.
- No mocking the database. Tests hit Postgres directly — fixture
  data is small and parallel-safe.
- No VCR / WebMock — no external HTTP in v1a (LLM is phase 1d).
- Coverage tooling (SimpleCov) intentionally skipped; coverage % is
  not what reviewers look at.

## Data model (v1a — 13 tables)

### Tenant / auth
- **Workspace** — `name`, `slug` (unique), `base_currency`, `settings` (jsonb)
- **User** — `email` (unique), `name`
- **Membership** — `workspace_id`, `user_id`, `role` (owner/admin/member/viewer)

### Ingestion
- **DataSource** — belongs to workspace; `name`, `kind`
  (bank/accounting/payment_processor/manual_csv), `currency`,
  `schema_mapping` (jsonb), `last_synced_at`, `discarded_at`
- **ImportBatch** — belongs to data_source + user; `status`
  (queued/processing/complete/failed), `row_count`, `processed_count`,
  `success_count`, `error_count`, `duplicate_count`, `error_log` (jsonb),
  `started_at`, `completed_at`. `has_one_attached :source_file`.

### Reconciliation core
- **ReconcilableItem** (parent, delegated_type) — belongs to workspace,
  data_source, import_batch; `amount_cents`, `amount_currency`,
  `occurred_on`, `description`, `external_id`, `external_id_hash`
  (unique per data_source), `status`
  (unmatched/proposed/matched/exception/ignored), `item_type`, `item_id`,
  `discarded_at`. Indexes: `(workspace_id, occurred_on)`,
  `(workspace_id, amount_cents)`, unique `(data_source_id,
  external_id_hash)`.
- **Match** — belongs to reconciliation_run, workspace, confirmed_by_user
  (optional); `confidence` (0..1), `method`
  (exact/rule/embedding/llm/manual), `status`
  (proposed/confirmed/rejected), `reasoning`, `discarded_at`.
- **MatchLeg** — belongs to match, reconcilable_item; `side` (a/b),
  `allocated_amount_cents`, `allocated_currency`. Unique
  `(match_id, reconcilable_item_id)`. Validates that confirmed
  allocations don't exceed the item's amount.
- **ReconciliationRun** — belongs to workspace, triggered_by_user,
  source_a (DataSource), source_b (DataSource); `date_range_start`,
  `date_range_end`, `status` (queued/running/complete/failed), `stats`
  (jsonb), `started_at`, `completed_at`, `error_message`.
- **ReconciliationException** — belongs to reconciliation_run,
  reconcilable_item, workspace, resolved_by_user (optional);
  `category` (timing/missing/duplicate/amount_mismatch/
  currency_mismatch/unknown), `llm_explanation`, `metadata` (jsonb,
  for structured exception context — ambiguity groups in v1a, LLM
  prompts/outputs in phase 1d), `resolved_at`, `resolution`
  (matched_manually/ignored/written_off). Unique
  `(reconciliation_run_id, reconcilable_item_id)`.

### Delegated subtypes
- **BankTransaction** — belongs to workspace (denormalized for direct
  querying); `posted_date`, `value_date`, `balance_after_cents`,
  `balance_after_currency`, `txn_type` (debit/credit), `counterparty`,
  `memo`, `check_number`, `raw_payload` (jsonb), `discarded_at`.
- **Invoice** — belongs to workspace; `invoice_number` (unique per
  workspace), `issue_date`, `due_date`, `total_cents`, `currency`,
  `status` (draft/open/partial/paid/void), `payer` (free text, since
  Customer is deferred), `notes`, `discarded_at`.

### Audit
- **AuditEvent** — belongs to workspace, user (optional), target
  (polymorphic, optional); `action`, `payload` (jsonb), `ip_address`,
  `user_agent`, `created_at` only. Immutable
  (`before_update`/`before_destroy` guards).

## Key design choices

- **`delegated_types`** for subtypes — shared parent `ReconcilableItem`
  for the matcher, typed children for domain fields. Children include
  `ReconcilableItem::Item` concern.
- **`MatchLeg`** handles splits (one invoice ↔ N payments) — no separate
  `PaymentApplication` table needed in v1.
- **Money columns** — `amount_cents` + `amount_currency` everywhere from
  day one. Workspace has `base_currency`. Multi-currency *plumbing*
  present, *FX conversion logic* deferred to v2.
- **Soft delete via `discard` gem** — opt-in scope (must explicitly use
  `.kept`, no default scope). On financial records and `Match`. Not on
  `AuditEvent` (immutable) or `ReconciliationRun`.
- **Importer pattern** — `Importers::Base` interface (Template Method
  for lifecycle/counters/error_log); v1a strategies are
  `Importers::FixedCsv` (canonical columns) and `Importers::MappedCsv`
  (reads `DataSource.schema_mapping`). `Importers::LlmInferred`
  (phase 1d) populates `schema_mapping` via Claude — schema doesn't
  change. `ImportBatchJob#importer_for` dispatches on
  `data_source.schema_mapping.present?`.
- **Signed-amount convention on `ReconcilableItem`** — positive =
  money in (invoices, bank credits), negative = money out (bank
  debits). Applied at import time so the matcher compares
  `amount_cents` directly without ever touching
  `BankTransaction.txn_type`. Keeps the matcher subtype-agnostic
  and gives directionality for free.
- **Matcher / Run lifecycle split** — `Matchers::ExactMatcher` is
  pure logic; `ReconciliationRunJob` owns the `queued → running →
  complete/failed` lifecycle and `started_at` / `completed_at`.
  Same split as `ImportBatchJob` + `Importers::Base`.
- **Ambiguity is a duplicate exception on both sides** — when two
  invoices both match one bank entry (or vice versa), every involved
  item gets `status: "exception"` and one
  `ReconciliationException(category: "duplicate")` row with the full
  group structure in `metadata` jsonb (group_key, involved_ids,
  reason). Never greedy-match — financial default is "do nothing
  rather than do wrong".
- **Two-layer status lifecycle** — `ReconcilableItem.status` (5
  values: `unmatched`/`proposed`/`matched`/`exception`/`ignored`)
  and `Match.status` (3 values: `proposed`/`confirmed`/`rejected`)
  intentionally exist as separate fields. Matcher transitions item
  `unmatched → proposed` and creates `Match(status: proposed)`. User
  confirm transitions `Match → confirmed` and `item → matched`.
  Direct `unmatched → matched` would skip the audit step required
  for financial review and would force LLM matches (low confidence)
  to auto-finalize. Keeping both layers preserves the confirmation
  semantics for phase 1c+ without schema change.
- **Single workspace in v1a** — seeded row, scoping habit preserved so
  1b multi-tenant refactor is painless.
- **Renamed `Exception` → `ReconciliationException`** to avoid collision
  with Ruby's built-in `Exception`.

## Alternatives considered (and rejected)

These are the design forks where we picked one path; preserving the
discarded options here so future-you (and reviewers) can see the
trade-off was deliberate, not accidental.

- **Storing ambiguity candidate IDs in `llm_explanation`** —
  rejected. Field name implies LLM-generated text; using it for
  structured ID lists would conflict semantically with phase 1d
  output. Chose `metadata` jsonb (added in v1a migration) instead.
- **Separate `ReconciliationExceptionGroup` + `Member` tables** for
  ambiguity groups — rejected as over-engineered for v1. The group
  concept is per-run; cross-run group correlation isn't a real
  query. `metadata.group_key` (UUID) handles the per-run UI
  correlation case with zero extra tables.
- **Hash-of-sorted-IDs as `group_key`** — rejected in favor of
  `SecureRandom.uuid`. A hash would change if the user manually
  resets some item statuses and re-runs the matcher, even though
  the "event" is conceptually the same. UUID is per-event;
  identity is stable through retries.
- **Matcher-side sign / `txn_type` filter** (matcher inspects
  `b.item.is_a?(BankTransaction) && b.item.txn_type == "credit"`) —
  rejected. Breaks the delegated_type abstraction; matcher would
  have to learn about each subtype as new ones are added (Payment in
  phase 1d). Chose to apply sign at import time so matcher only ever
  reads parent fields.
- **`FixedCsv` auto-detects Format A vs Format B** — rejected.
  "Fixed" in the class name promises a single canonical schema;
  making it smart would blur the line with `MappedCsv` and
  `LlmInferred`. Format A goes through `MappedCsv` (the mapping
  simply omits `txn_type`).
- **Interactive column-mapping wizard UI in v1** — rejected for
  v1, scheduled for v1.1. The backend (`MappedCsv` +
  `DataSource.schema_mapping`) is fully wired in v1a; v1 ships with
  a JSON textarea on `DataSources#edit` for setting the mapping.
  Wizard wireframe documented in README roadmap.
- **Application-level `reload` + status recheck (no DB lock)** —
  rejected, because it only protects against stale in-memory state
  within one process, not against concurrent workers. Two workers
  could both reload, both see `unmatched`, both create a Match —
  the recheck doesn't help because they read independently. v1a uses
  `SELECT FOR UPDATE` via `.lock.find(id)` instead (real serializer)
  and so does NOT carry a "single-worker assumption" caveat.
- **Partial unique index on `match_legs(reconcilable_item_id)`
  filtered by non-rejected matches** — deferred to phase 1c+ as
  defense-in-depth. The FOR UPDATE row lock makes it unnecessary
  for v1a correctness; the index would be belt to the lock's
  suspenders, catching bugs in future code paths that forget to
  lock. Not worth the index maintenance cost in v1a.
- **Skipping the testing pyramid (only unit tests)** — rejected.
  Unit alone doesn't prove the controllers / job / Active Storage
  wiring is correct, and the JD explicitly calls out "different
  testing types". v1a adds request + integration tiers (see
  "Testing strategy").

## Explicitly deferred to v2 (don't re-add without revisiting)

- FX rate fetching, FX gain/loss, `base_amount_cents`/`fx_rate_id`/
  `fx_converted_at` columns on `ReconcilableItem`
- pgvector embeddings on `ReconcilableItem`
- `LineItem` (invoice details)
- `PaymentApplication` (replaced by `MatchLeg` in v1)
- `Customer` model — invoices use free-text `payer` field in v1
- `LedgerEntry` subtype
- `Rule.created_from_match_id` learning loop (rules are user-authored in
  v1, not auto-generated from confirmations)
- Invoice `subtotal_cents` / `tax_cents`
- `Customer.external_ids`

## Gotchas worth remembering (Django → Rails)

1. **Migrations are one-shot recipes.** Editing an applied migration
   does NOT change the DB. To change schema after a migration ran:
   - dev: `bin/rails db:migrate:reset` (drop + create + migrate)
   - prod: write a NEW migration that alters the existing table
2. **DB constraints vs model validations** — Rails splits them. NOT
   NULL / defaults / unique go in migrations; presence / length /
   format go in `validates ...` in the model.
3. **`discard` opts in to filtering.** `Invoice.all` returns everything;
   you have to write `Invoice.kept` explicitly. Unlike
   `django-safedelete` which overrides the default manager.
4. **`bin/` is committed.** Rails binstubs are project scripts, not a
   virtualenv. They lock you to the project's gem versions.
5. **`db/schema.rb` is auto-generated** on every migrate and committed.
   It's the canonical "current DB shape" view.
6. **Rails fixtures bypass model validations** — `MyString`
   placeholder data from `rails generate model` will pass YAML
   parsing but blow up on unique indexes at load time. Either
   rewrite fixtures with valid data or comment them out (`# empty`).
   Affects `fixtures :all` in `test_helper.rb`.
7. **`mise install` on macOS may fail building Ruby from source**
   (psych / openssl issues). Workaround: `mise settings
   ruby.compile=false` to download a precompiled binary instead.
   Documented because next contributor will hit it.
8. **Postgres 17 install via brew** does not auto-add `psql` to
   PATH on Apple Silicon. After `brew install postgresql@17`:
   `echo 'export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"'
   >> ~/.zshrc`. `bin/rails db:*` works without this; only direct
   `psql` use needs it.
9. **`jsonb` columns accept any JSON value, not just Hash.** Rails
   doesn't coerce — `data_source.update!(schema_mapping: "")` stores
   the string `""`, not `{}`. PG accepts because `""` (and `null`)
   are valid JSON. Means `present?` / `.[]` / `.each` can crash
   downstream. Always: (1) validate at the model level
   (`is_a?(Hash)`), (2) parse-then-assign at the controller level
   when input comes from a textarea / form, (3) trust the DB
   default (`default: {}, null: false`) only for newly-created rows
   that never get updated.
