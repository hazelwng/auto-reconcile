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
5. Seed: 1 user, 1 workspace, 1 membership, 2 data sources
6. Importers: `Importers::Base` + `Importers::FixedCsv`, `ImportBatchJob`
7. Matchers: `Matchers::ExactMatcher`, `ReconciliationRunJob`
8. Controllers, routes, Hotwire views
9. Sample CSV fixtures
10. End-to-end manual test

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
`ReconciliationException.llm_explanation`.

## Matching pipeline (tiered, cheapest-first)

1. **Exact match** — same amount, same currency, same/close date.
2. **Rule match** — user-authored patterns (phase 1c).
3. **LLM adjudication** — Claude with structured output for ambiguous
   candidates (phase 1d).
4. **Human review** — anything below confidence threshold goes to a
   review queue. Confirmations could later train rules (deferred).

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
  currency_mismatch/unknown), `llm_explanation`, `resolved_at`,
  `resolution` (matched_manually/ignored/written_off). Unique
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
- **Importer pattern** — `Importers::Base` interface, v1a has
  `Importers::FixedCsv` with canonical columns. Later
  `Importers::LlmInferred` will call Claude once per DataSource to
  populate `DataSource.schema_mapping` jsonb — schema doesn't change.
- **Single workspace in v1a** — seeded row, scoping habit preserved so
  1b multi-tenant refactor is painless.
- **Renamed `Exception` → `ReconciliationException`** to avoid collision
  with Ruby's built-in `Exception`.

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
