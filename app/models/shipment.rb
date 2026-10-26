class Shipment < ApplicationRecord
  has_many :shipment_events,
           -> { order(:event_timestamp, :event_id) },
           inverse_of: :shipment

  validates :shipment_reference, presence: true, uniqueness: true

  def status_summary
    statuses = shipment_events.map(&:status).uniq
    terminal_statuses = statuses & %w[delivered failed]

    if terminal_statuses.length > 1
      return { current_status: nil, status_resolution: "undetermined" }
    end

    current_status = statuses.max_by { |status| ShipmentEvent::STATUS_RANK.fetch(status) }
    {
      current_status: current_status,
      status_resolution: current_status ? "determined" : "undetermined"
    }
  end

  def summary_json
    { shipment_reference: shipment_reference }.merge(status_summary)
  end
end
