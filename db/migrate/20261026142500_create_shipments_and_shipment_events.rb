class CreateShipmentsAndShipmentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :shipments do |t|
      t.string :shipment_reference, null: false
    end
    add_index :shipments, :shipment_reference, unique: true

    create_table :shipment_events, id: :uuid, primary_key: :event_id do |t|
      # PostgreSQL does not automatically index foreign keys; this supports event lookup by shipment.
      t.references :shipment, null: false, foreign_key: true, index: true
      t.string :status, null: false
      t.datetime :event_timestamp, null: false
    end
  end
end
