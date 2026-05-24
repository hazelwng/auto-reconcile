# auto-reconcile

A minimal financial reconciliation web app. Configure data sources, import CSVs of accounting invoices and bank transactions, then run an exact matcher that pairs them up and flags ambiguities.

## Stack

- Rails 8.1 (Ruby 3.4.9 via `mise`)
- PostgreSQL 17 (single DB; Solid Queue / Cache / Cable tables live alongside the app's tables)
- SolidQueue (background jobs), Solid Cache, Solid Cable
- Hotwire (Turbo + Stimulus), importmap, Tailwind via cssbundling
- Active Storage on local disk (v1)

## Local setup

```bash
mise install                 # Ruby 3.4.9
bundle install
bin/rails db:prepare         # creates the dev DB and runs migrations
bin/rails db:fixtures:load   # seeds a demo workspace, user, and 2 data sources
bin/dev                      # boots web + tailwind watcher + SolidQueue worker
```

App runs at <http://localhost:3000>.

## Three-step user flow

1. **Configure a data source** — `/data_sources` (an accounting source and a bank source, already seeded by fixtures)
2. **Import a CSV into a source** — `/import_batches/new`. Sample CSVs in `tmp/demo_invoices.csv` and `tmp/demo_bank.csv` reproduce the canonical end-to-end demo (1 exact match + 1 ambiguity group of 3 + 1 unmatched invoice).
3. **Run reconciliation** — `/reconciliation_runs/new`. Pick the two sources and a date range; the background job runs ExactMatcher and you'll see matches + exceptions on the show page.

## Testing

```bash
bin/rails test                  # full suite (models, services, controllers, jobs)
bin/rails test:system           # none yet
```

## Deploy to Railway

This app is set up for a **single-container** Railway deployment: web (Puma) and the SolidQueue worker run together inside Puma's master process via the `plugin :solid_queue` line in `config/puma.rb`, gated on `SOLID_QUEUE_IN_PUMA=1`.

### 1. Create the Railway project

- New project → "Deploy from GitHub repo" → pick this repo.
- Add a Postgres service to the project.

### 2. Set env vars on the web service

| Variable | Value |
| --- | --- |
| `RAILS_MASTER_KEY` | Contents of your local `config/master.key` |
| `DATABASE_URL` | The **public** Postgres URL from the Postgres service's "Connect" tab (the one ending in `.proxy.rlwy.net:<port>`, not `postgres.railway.internal`). Solid Queue / Cache / Cable tables live in this same DB. |
| `SOLID_QUEUE_IN_PUMA` | `1` |
| `APP_HOST` | Optional — your custom domain (Railway's `*.up.railway.app` is already allowed) |

> **Why the public URL?** Railway's private hostname `postgres.railway.internal` only resolves over IPv6 on the project's private network and has known boot-time DNS-warm-up races that crash the SolidQueue dispatcher (`could not translate host name … Temporary failure in name resolution`). The public URL goes over Railway's TCP proxy with TLS — slightly more latency, much less to debug. If you need private networking later, enable it on both services and switch back.

### 3. Deploy and smoke-test

- Railway will build the Dockerfile and `bin/docker-entrypoint` runs `db:prepare` on boot.
- `curl https://<app>.up.railway.app/up` should return 200.
- Walk the 3-step flow in the browser. If the SolidQueue worker is running correctly, ImportBatchJob and ReconciliationRunJob will execute and you'll see results.

### Caveats

- **No auth in v1.** Anyone with the URL can use the demo workspace. Share the URL selectively. Basic auth lands in a follow-up PR before broader sharing.
- **Active Storage is ephemeral.** Uploaded CSVs live on the container's local disk and disappear on every redeploy. Fine for a demo; move to S3 or a Railway volume before treating uploads as durable.
