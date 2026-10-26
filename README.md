# Shipment Event Service

A small Ruby on Rails API backed by PostgreSQL. It accepts carrier events idempotently, preserves event history, and returns shipment timelines plus current status derived from logical lifecycle order.

## Requirements

- Docker Desktop or Docker Engine with Docker Compose v2 for the containerized demo
- Ruby 4.0.9, Bundler 4.x, and PostgreSQL for running Rails directly on the host

## Run with Docker Compose

From the repository root, build the Rails image and start the API plus its private PostgreSQL 16 container:

```sh
docker compose build
docker compose up
```

For a single build-and-start command, use `docker compose up --build`. The API is available at `http://localhost:3000`; PostgreSQL is reachable only on the Compose network, so it will not conflict with a host database on port 5432. The demo database uses a named volume and keeps its data across `docker compose down`. Compose binds the API to loopback and uses demo-only credentials; do not expose this configuration as a production deployment.

In another terminal, replay the bundled fixture from inside the running service container:

```sh
docker compose exec -e BASE_URL=http://127.0.0.1:3000 web ruby script/replay_events.rb --concurrency 8
```

Stop the containers with `docker compose down`. To also delete the persisted demo database, use `docker compose down -v` (this removes the Compose volume and its data).

## Run locally without Docker

From the repository root:

```sh
# Create a local-only environment file if you do not already have one.
test -f .env || cp .env.example .env
# Edit .env with the PostgreSQL credentials for this machine.
set -a
. ./.env
set +a
bundle install
bin/rails db:prepare
bin/rails server -p 3000
```

The server listens at `http://localhost:3000`. `.env` is ignored by Git. Rails does not load `.env` by itself; the `source` commands above export its development `DATABASE_URL`. Tests use a separate ignored `.env.test` file with its own `DATABASE_URL`, so the test suite cannot accidentally target the development database. Copy `.env.test.example` to `.env.test` and edit its credentials if needed.

In another terminal, source `.env.test` and run the test suite against its separate database:

```sh
test -f .env.test || cp .env.test.example .env.test
set -a
. ./.env.test
set +a
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rails test
```

## Replay the supplied CSV

The fixture is included in this repository at `data/carrier_events.csv`. From the repository root:

```sh
CSV_PATH=data/carrier_events.csv ruby script/replay_events.rb --concurrency 8
```

The replay sends each CSV row to the webhook, including repeated IDs, and reports request outcomes. After it completes, inspect the timeline and status through the API. Re-running the replay should not add duplicate event rows or change results.

## API examples

Ingest one carrier event:

```sh
curl -i -X POST http://localhost:3000/webhooks/carrier_events \
  -H 'Content-Type: application/json' \
  -d '{"event_id":"31c80297-3c07-49e0-b07d-3cc26ebbf8eb","shipment_reference":"TV-200070","status":"created","event_timestamp":"2026-07-06T09:08:00Z"}'
```

Read one shipment’s timeline and current status:

```sh
curl -s http://localhost:3000/shipments/TV-200070
```

List shipments with a known current status, or find shipments whose terminal events conflict:

```sh
curl -s 'http://localhost:3000/shipments?status=delivered'
curl -s 'http://localhost:3000/shipments?status=undetermined'
```

## Development approach

This project uses a document-first, interface-first, test-driven loop: domain invariants and trade-offs live in the technical design and ADR; OpenAPI specifies the HTTP contract before controller behavior; Minitest integration tests capture the observable correctness rules; and replay validates the contract against the full fixture. This makes decisions reviewable and surfaces mismatches early.

The endpoint contract is in [`docs/openapi.yaml`](docs/openapi.yaml); design choices and the Mermaid ER diagram are in [`docs/technical-design.md`](docs/technical-design.md). The required trade-off and future async design note are in [`docs/adr/0001-storage-idempotency-and-query-model.md`](docs/adr/0001-storage-idempotency-and-query-model.md).

## Design decisions

- **Two tables:** `shipments` represents the shipment identity and uniquely indexes `shipment_reference`; `shipment_events` is the immutable event log. `event_id` (UUID) is the event primary key and idempotency key.
- **Idempotency:** exact replays are successful no-ops. A repeated ID with changed immutable fields returns `409 Conflict`; existing event data is never overwritten.
- **Current status:** derive the highest logical lifecycle rank (`created < picked_up < in_transit < delivered/failed`), independently of event arrival time. Forward skips are allowed. If both terminal outcomes exist, retain both events and return `current_status: null` with `status_resolution: "undetermined"`.
- **Timeline:** order in PostgreSQL by `event_timestamp, event_id`; this is chronological history, separate from logical current status.
- **Indexes:** primary key on `event_id`, unique index on `shipment_reference`, and an index on event `shipment_id` for timeline lookup. With fewer than five events per shipment in this fixture, do not index `event_timestamp`; sort the small result set in SQL. Revisit with `EXPLAIN ANALYZE` as volume grows.
- **Scope:** synchronous HTTP ingestion and query APIs only. No authentication, frontend, Sidekiq, deployment, or downstream event publishing.
- **Tooling:** Rails API mode, PostgreSQL, and built-in Minitest keep the demo small and avoid extra framework dependencies.

## What I would do next

1. Validate lifecycle and terminal-conflict rules with the carrier/product owner, including a remediation path for undetermined shipments.
2. Add metrics for duplicate deliveries, payload mismatches, and undetermined statuses; retain structured request logs and replay summaries.
3. When `shipment_events` reaches millions of rows, add bounded keyset pagination to timelines using `(event_timestamp, event_id)` as the stable cursor and ordering key; include the event ID so equal timestamps paginate deterministically. Measure the query plan before adding `(shipment_id, event_timestamp, event_id)`, and assess status projection and shipment-list pagination separately.
4. For multi-carrier or multi-tenant use, scope event identity and shipment references to the carrier/account and add authorization at the service boundary.
5. If ingestion needs asynchronous processing, design an internal durable queue/outbox and idempotent workers; downstream event publication remains a separate requirement.
6. Add an optional, lightweight pre-commit check for RuboCop and fast tests once the team agrees on a low-friction workflow; keep CI as the authoritative check.

## AI-usage note

Manus AI assisted with the initial Rails API scaffold, fixture analysis, and drafts of the technical design, API contract, ADR, README, and tests. The candidate reviewed the work and made the domain decisions, including logical status ordering, terminal-conflict handling, index scope, and the two-table model. An early AI assumption treated the newest `event_timestamp` as current status; review caught that status must follow logical lifecycle order while the timeline remains timestamp-ordered, and the design was corrected. No business rule was accepted without review.
