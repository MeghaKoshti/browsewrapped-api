class CreateSharedReports < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_reports do |t|
      t.string   :token, null: false
      t.jsonb    :data, null: false, default: {}
      t.string   :delete_token_digest, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :shared_reports, :token, unique: true
    add_index :shared_reports, :expires_at
  end
end
