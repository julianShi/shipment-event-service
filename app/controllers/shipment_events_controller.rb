class ShipmentEventsController < ApplicationController
  def index
    requested_status = params[:status].presence
    if requested_status && !ShipmentEvent::STATUSES.include?(requested_status)
      return render json: { error: "invalid_status_filter" }, status: :unprocessable_entity
    end

    events = ShipmentEvent.includes(:shipment).joins(:shipment)
    shipment_reference = params[:shipment_reference].to_s.strip
    if shipment_reference.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(shipment_reference)}%"
      events = events.where("shipments.shipment_reference ILIKE ?", pattern)
    end
    events = events.where(status: requested_status) if requested_status
    events = events.order(event_timestamp: :desc, event_id: :desc)

    render json: {
      events: events.map do |event|
        {
          event_id: event.event_id,
          shipment_reference: event.shipment.shipment_reference,
          status: event.status,
          event_timestamp: event.event_timestamp.iso8601(6)
        }
      end
    }
  end
end
