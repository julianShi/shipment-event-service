class ShipmentEvent < ApplicationRecord
  self.primary_key = "event_id"

  STATUSES = %w[created picked_up in_transit delivered failed].freeze
  STATUS_RANK = {
    "created" => 0,
    "picked_up" => 1,
    "in_transit" => 2,
    "delivered" => 3,
    "failed" => 3
  }.freeze

  belongs_to :shipment, inverse_of: :shipment_events

  validates :event_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :event_timestamp, presence: true
end
