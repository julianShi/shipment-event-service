# Shipment Events UI — Design

## Goal

Provide a small, read-only operator view for browsing the carrier events stored by Shipment Event Service. The primary screen is a two-dimensional table of shipment events with two filters: shipment reference and event status. Keep the interface focused on inspection; event ingestion, editing, authentication, and shipment-list workflows are not part of this UI slice.

## Page structure

1. **Page title:** `Shipment Events`, with a short description such as `Browse carrier tracking events`.
2. **Filters:** place both controls above the table, in this order:
   - **Shipment reference:** text input, placeholder `Filter by shipment reference`.
   - **Event status:** select with `All statuses` (default), `created`, `picked_up`, `in_transit`, `delivered`, and `failed`.
   - **Clear filters:** reset both controls and return to the unfiltered event list. Disable it when no filter is active.
3. **Result count:** show the number of matching events when the response provides a total; otherwise show the number currently loaded.
4. **Events table:** one row per persisted shipment event. Proposed columns:

   | Column | Display |
   | --- | --- |
   | Shipment reference | Carrier shipment identifier; visually primary and easy to scan |
   | Status | Event-level status, displayed as a text label (optionally with a restrained color treatment) |
   | Event timestamp | Human-readable timestamp, with the exact ISO-8601 timestamp available on hover or copy |
   | Event ID | UUID, visually secondary but selectable/copyable for support and idempotency investigations |

**Scope decision:** this is the **shipment-events view, not a shipments view**. Each row represents one event, and the `Status` column shows that event's `status`. It must not be labeled or interpreted as the shipment's derived `current_status`, which belongs to shipment summaries and can differ from the status of a particular event. A separate shipment summary/detail view would be a different UI.

## Filter behavior

- Filters combine with **AND**: when both are set, show events matching the shipment-reference query and event status.
- Shipment reference is a case-insensitive substring search so a user can find an identifier from a partial value. Trim surrounding whitespace; an empty value is treated as no filter.
- Event status matches the event row's own `status`, not the shipment's derived current status. `undetermined` is not an event status; it describes a shipment whose terminal events conflict and therefore is not an option in this event-status select.
- Apply text filtering after a short debounce (about 250–300 ms) and on Enter; apply status changes immediately. Do not issue a request when neither filter has changed.
- Preserve active filter values in URL query parameters (`shipment_reference` and `status`) so the view can be refreshed or shared. The browser URL contains no credentials or private data beyond the entered shipment reference.
- Provide an explicit clear action rather than an ambiguous reset icon.

## Ordering and timestamps

For the initial view, order newest event first by `event_timestamp` descending, with `event_id` descending as a deterministic tie-breaker. Keep the timestamp timezone explicit in the rendered value or tooltip; never imply that event time is arrival/ingestion time. If a user opens a single-shipment timeline view later, that view should retain the API's chronological ascending order.

## Loading, empty, and error states

- **Loading:** keep the table structure in place and show a concise loading indicator; avoid replacing the entire page with a blank screen.
- **No filters, no events:** show `No shipment events yet`.
- **Filters yield no matches:** show `No events match these filters` and keep the active filter values visible with the clear action available.
- **Request failure:** show a non-technical message and a retry action; do not silently display stale results as current.
- **Malformed or unsupported status:** prevent it through the select control; still render a useful validation message if the API rejects a request.

## Accessibility and responsive behavior

Use programmatic labels for both filters, semantic table markup with a caption or accessible heading, and column headers scoped to columns. All controls must be keyboard operable with visible focus. Status meaning must be expressed in text and not color alone. On narrow screens, retain every column and allow horizontal table scrolling rather than truncating the event ID or timestamp without access to its full value.

## API contract implications

The current API is not sufficient for this screen as described:

- `GET /shipments` returns shipment summaries and supports a filter on each shipment's **derived current status**.
- `GET /shipments/:shipment_reference` returns one shipment's ordered event history.
- Calling the detail endpoint once for every shipment would create an inefficient N+1 request pattern, and the list endpoint does not return event rows.

The UI uses `GET /shipment_events`, with optional `shipment_reference` (case-insensitive substring) and `status` (event status) query parameters. The endpoint combines active filters, returns event-level fields (`event_id`, `shipment_reference`, `status`, `event_timestamp`), orders deterministically, and rejects unsupported status values. It is distinct from `GET /shipments?status=...`, whose meaning remains derived shipment status.

The fixture contains about 1,000 rows, so the first UI iteration loads the full filtered result set. Do not fetch all shipment details separately. If event volume grows substantially, add bounded cursor pagination; the stable sort key should include both `event_timestamp` and `event_id` so timestamps that tie neither skip nor repeat records between pages. Keep the OpenAPI contract and backend tests in sync with any query changes.

## MVP acceptance criteria

1. The page renders the event table with one row per returned event and the four columns above.
2. A user can filter by a full or partial shipment reference and by event status independently or together.
3. Clearing filters restores the unfiltered table.
4. Filter semantics are clearly event-level and cannot be confused with `current_status` filtering.
5. Loading, no-results, and request-error states are understandable and keyboard-accessible.
6. The frontend uses one filtered event-list request, not a request per shipment.

## Assumptions and open decisions

- This is a read-only MVP; no event ingestion form or mutation controls are included.
- The status filter means **event status** because the table lists event rows. If product intent is instead to filter by each shipment's current status, the query semantics must be named separately and the API must define how matching shipments' events are included.
- The initial fixture-sized table has no pagination control. Cursor pagination is a scaling follow-up, not a promise to return unbounded histories forever.
- The MVP is implemented as a same-origin static page in `public/` using vanilla HTML, CSS, and JavaScript, without a frontend build toolchain. Product branding, deployment, and authorization remain outside this design document's scope.
