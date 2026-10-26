class ShipmentsController < ApplicationController
  def index
    requested_status = params[:status]
    allowed_statuses = ShipmentEvent::STATUSES + [ "undetermined" ]

    if requested_status.present? && !allowed_statuses.include?(requested_status)
      return render json: { error: "invalid_status_filter" }, status: :unprocessable_entity
    end

    shipments = Shipment.includes(:shipment_events).order(:shipment_reference).to_a
    summaries = shipments.map(&:summary_json)
    if requested_status.present?
      summaries.select! do |summary|
        if requested_status == "undetermined"
          summary.fetch(:status_resolution) == "undetermined"
        else
          summary.fetch(:current_status) == requested_status
        end
      end
    end

    render json: { shipments: summaries }
  end

  def show
    shipment = Shipment.includes(:shipment_events).find_by!(shipment_reference: params[:shipment_reference])
    events = shipment.shipment_events.map do |event|
      {
        event_id: event.event_id,
        shipment_reference: shipment.shipment_reference,
        status: event.status,
        event_timestamp: event.event_timestamp.iso8601(6)
      }
    end

    render json: shipment.summary_json.merge(events: events)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "shipment_not_found" }, status: :not_found
  end
end
