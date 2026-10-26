require "test_helper"

class ShipmentEventsApiTest < ActionDispatch::IntegrationTest
  test "an exact duplicate is a no-op and a reused ID with different data conflicts" do
    payload = event_payload(
      event_id: "00000000-0000-0000-0000-000000000001",
      shipment_reference: "TV-IDEMPOTENT",
      status: "created",
      event_timestamp: "2026-07-01T10:00:00Z"
    )

    post_event(payload)
    assert_response :created
    assert_equal false, response_json.dig("duplicate")

    post_event(payload)
    assert_response :ok
    assert_equal true, response_json.dig("duplicate")

    get "/shipments/TV-IDEMPOTENT"
    assert_response :ok
    assert_equal 1, response_json.fetch("events").length

    conflicting_payload = payload.merge(
      "shipment_reference" => "TV-IDEMPOTENT-OTHER",
      "status" => "picked_up"
    )
    post_event(conflicting_payload)
    assert_response :conflict

    get "/shipments/TV-IDEMPOTENT"
    assert_response :ok
    assert_equal "created", response_json.fetch("events").first.fetch("status")
    assert_equal 1, response_json.fetch("events").length

    get "/shipments/TV-IDEMPOTENT-OTHER"
    assert_response :not_found
  end

  test "current status follows logical rank while the timeline follows event time" do
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000002",
      shipment_reference: "TV-ORDERING",
      status: "in_transit",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    # A later timestamp must not make this lower-rank event the current status.
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000003",
      shipment_reference: "TV-ORDERING",
      status: "created",
      event_timestamp: "2026-07-03T10:00:00Z"
    ))
    assert_response :created

    get "/shipments/TV-ORDERING"
    assert_response :ok
    body = response_json
    assert_equal "in_transit", body.fetch("current_status")
    assert_equal "determined", body.fetch("status_resolution")
    assert_equal %w[in_transit created], body.fetch("events").map { |event| event.fetch("status") }
  end

  test "a forward lifecycle skip is accepted and derives the furthest status" do
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000004",
      shipment_reference: "TV-SKIP",
      status: "picked_up",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000005",
      shipment_reference: "TV-SKIP",
      status: "failed",
      event_timestamp: "2026-07-02T10:00:00Z"
    ))
    assert_response :created

    get "/shipments/TV-SKIP"
    assert_response :ok
    assert_equal "failed", response_json.fetch("current_status")
  end

  test "conflicting terminal outcomes are retained and reported as undetermined" do
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000006",
      shipment_reference: "TV-TERMINAL-CONFLICT",
      status: "delivered",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000007",
      shipment_reference: "TV-TERMINAL-CONFLICT",
      status: "failed",
      event_timestamp: "2026-07-02T10:00:00Z"
    ))
    assert_response :created

    get "/shipments/TV-TERMINAL-CONFLICT"
    assert_response :ok
    body = response_json
    assert_nil body.fetch("current_status")
    assert_equal "undetermined", body.fetch("status_resolution")
    assert_equal 2, body.fetch("events").length

    get "/shipments", params: { status: "undetermined" }
    assert_response :ok
    assert_equal [ "TV-TERMINAL-CONFLICT" ], response_json.fetch("shipments").map { |shipment| shipment.fetch("shipment_reference") }
  end

  test "shipment list filters by derived status" do
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000008",
      shipment_reference: "TV-DELIVERED",
      status: "delivered",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000009",
      shipment_reference: "TV-IN-TRANSIT",
      status: "in_transit",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    get "/shipments", params: { status: "delivered" }
    assert_response :ok
    assert_equal [ "TV-DELIVERED" ], response_json.fetch("shipments").map { |shipment| shipment.fetch("shipment_reference") }
  end

  test "timeline ties are deterministically ordered by event ID" do
    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000011",
      shipment_reference: "TV-TIE",
      status: "created",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    post_event(event_payload(
      event_id: "00000000-0000-0000-0000-000000000010",
      shipment_reference: "TV-TIE",
      status: "created",
      event_timestamp: "2026-07-01T10:00:00Z"
    ))
    assert_response :created

    get "/shipments/TV-TIE"
    assert_response :ok
    assert_equal [ "00000000-0000-0000-0000-000000000010", "00000000-0000-0000-0000-000000000011" ],
                 response_json.fetch("events").map { |event| event.fetch("event_id") }
  end

  private

  def post_event(payload)
    post "/webhooks/carrier_events", params: payload, as: :json
  end

  def response_json
    JSON.parse(response.body)
  end

  def event_payload(event_id:, shipment_reference:, status:, event_timestamp:)
    {
      "event_id" => event_id,
      "shipment_reference" => shipment_reference,
      "status" => status,
      "event_timestamp" => event_timestamp
    }
  end
end
