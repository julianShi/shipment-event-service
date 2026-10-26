# ADR 0001: Shipment event storage, idempotency, and query model

- **Status:** Accepted
- **Date:** 2026-10-26

## Context

Carrier webhooks can be duplicated and arrive out of order. The service must expose an accurate timeline and current shipment status after replay. The supplied fixture has 997 rows, 941 unique event IDs, 310 shipment references, and fewer than five distinct events per shipment. The assignment asks for shipments and their events, a timeline endpoint, and a shipment list filterable by status.

## Decisions

**Use two tables.** `shipments` gives `shipment_reference` a unique identity and a stable place for shipment-level state. `shipment_events` stores immutable carrier facts and references a shipment through a foreign key. A single table keyed by reference could work for this small CSV, but would make the shipment entity implicit and weaken the explicit parent/child model requested by the brief.

**Use the carrier UUID `event_id` as the event primary key and idempotency key.** PostgreSQL’s primary-key constraint is the race-safe duplicate guard. An exact repeat is a successful no-op because that immutable event is already persisted; overwriting would turn retries into mutation, make results arrival-order-dependent, and destroy the original fact. If the same ID arrives with different fields, return `409 Conflict` and preserve the stored event. In a multi-carrier system, event identity may need to be scoped by carrier.

**Separate timeline order from current-state order.** Store every unique valid event. Sort timeline responses in SQL by `(event_timestamp, event_id)`. Derive current status by logical rank: `created < picked_up < in_transit < delivered | failed`; permit forward skips and never regress for a late lower-rank event. `delivered` and `failed` are mutually exclusive terminal branches. If both exist, keep both raw events, return `current_status: null` and `status_resolution: "undetermined"`, and expose those shipments through `status=undetermined` rather than inventing precedence.

**Use only indexes justified by identity and lookup needs.** The event primary key indexes `event_id`; a unique index supports lookup by `shipment_reference`; a non-unique index on `shipment_events.shipment_id` supports fetching a shipment’s timeline and the foreign-key relationship. The fixture has under five events per shipment, so the database can cheaply sort each result set; do not add an `event_timestamp` or composite timeline index yet. Add one only if representative `EXPLAIN ANALYZE` measurements show a benefit at larger volume. No status index is needed while current status is derived from events.

**Keep the initial service synchronous and query-oriented.** Consumers read through the shipment APIs; no downstream event publishing, Sidekiq, or queue is required. The assignment’s async note is design-only: if ingestion later needs asynchronous processing, durably accept events behind an internal outbox/queue, process at least once with idempotent workers, and support retries/dead-letter inspection. This does not imply downstream fan-out.

## Consequences

The event log is the source of truth and can rebuild status. Unique constraints make duplicate behavior safe under concurrent requests. The schema and code stay simple for the demo; current-status filtering requires deriving each shipment’s status, but the fixture is small. Larger data volumes may justify a rebuildable shipment status projection and a composite timeline index, based on measurements rather than speculation.
