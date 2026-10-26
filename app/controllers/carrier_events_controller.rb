require "time"

class EventIdPayloadConflict < StandardError; end

class CarrierEventsController < ApplicationController
  wrap_parameters false

  REQUIRED_FIELDS = %w[event_id shipment_reference status event_timestamp].freeze
  UUID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

  def create
    payload = params.permit(*REQUIRED_FIELDS).to_h
    missing = REQUIRED_FIELDS.reject { |field| payload[field].present? }
    return render_error("missing_fields", details: { fields: missing }) if missing.any?

    unknown = params.keys.map(&:to_s) - REQUIRED_FIELDS - %w[controller action format]
    return render_error("unknown_fields", details: { fields: unknown }) if unknown.any?

    unless payload.fetch("event_id").match?(UUID_PATTERN)
      return render_error("invalid_event_id", details: { field: "event_id" })
    end

    unless ShipmentEvent::STATUSES.include?(payload.fetch("status"))
      return render_error("invalid_status", details: { allowed: ShipmentEvent::STATUSES })
    end

    begin
      parsed_timestamp = Time.iso8601(payload.fetch("event_timestamp")).utc
      event_timestamp = Time.at(parsed_timestamp.to_i, parsed_timestamp.usec, :microsecond)
    rescue ArgumentError, TypeError
      return render_error("invalid_event_timestamp", details: { field: "event_timestamp" })
    end

    shipment = nil
    inserted = false

    Shipment.transaction do
      Shipment.insert_all([ { shipment_reference: payload.fetch("shipment_reference") } ])
      shipment = Shipment.find_by!(shipment_reference: payload.fetch("shipment_reference"))
      result = ShipmentEvent.insert_all(
        [ {
          event_id: payload.fetch("event_id"),
          shipment_id: shipment.id,
          status: payload.fetch("status"),
          event_timestamp: event_timestamp
        } ],
        returning: %w[event_id]
      )
      inserted = result.rows.any?

      unless inserted
        existing = ShipmentEvent.includes(:shipment).find_by!(event_id: payload.fetch("event_id"))
        matches_existing =
          existing.shipment.shipment_reference == payload.fetch("shipment_reference") &&
          existing.status == payload.fetch("status") &&
          existing.event_timestamp.utc == event_timestamp
        raise EventIdPayloadConflict unless matches_existing
      end
    end

    render json: {
      event_id: payload.fetch("event_id"),
      duplicate: !inserted,
      shipment: shipment.summary_json
    }, status: inserted ? :created : :ok
  rescue EventIdPayloadConflict
    render_error("event_id_conflict", status: :conflict)
  rescue ActiveRecord::RecordInvalid => error
    render_error("invalid_event", details: { message: error.record.errors.full_messages })
  end

  private

  def render_error(error, status: :unprocessable_entity, details: {})
    render json: { error: error, details: details }, status: status
  end
end
