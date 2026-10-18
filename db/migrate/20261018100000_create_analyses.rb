class CreateAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :analyses, id: :uuid do |t|
      t.string  :status, null: false, default: "pending"
      t.string  :source, null: false, default: "upload"
      t.string  :filename
      t.text    :error_message
      t.jsonb   :result
      t.integer :entries_count

      t.timestamps
    end

    add_index :analyses, :status
    add_index :analyses, :created_at
  end
end
