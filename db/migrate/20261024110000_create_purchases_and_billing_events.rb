class CreatePurchasesAndBillingEvents < ActiveRecord::Migration[8.1]
  def change
    # One row per successful payment. A Pass is "active" while any
    # non-revoked purchase for the email has valid_until in the future.
    create_table :purchases do |t|
      t.string   :email, null: false
      t.string   :plan, null: false
      t.integer  :amount, null: false # smallest currency unit (paise, cents)
      t.string   :currency, null: false
      t.string   :provider, null: false
      t.string   :provider_ref, null: false # the provider's payment id
      t.datetime :valid_until, null: false
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :purchases, %i[provider provider_ref], unique: true
    add_index :purchases, %i[email valid_until]

    # Every webhook we have processed, so retries are ignored. Only ids and
    # the event type are kept, never the payload (it holds customer details).
    create_table :billing_events do |t|
      t.string :provider, null: false
      t.string :provider_event_id, null: false
      t.string :event_type, null: false
      t.string :payment_ref

      t.timestamps
    end
    add_index :billing_events, %i[provider provider_event_id], unique: true
  end
end
