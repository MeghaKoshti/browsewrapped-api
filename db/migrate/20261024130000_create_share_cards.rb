class CreateShareCards < ActiveRecord::Migration[8.1]
  def change
    # The persona PNG shown in link previews. Kept in Postgres (bytea): cards
    # are small (<= 300 KB), live and die with their share, and survive Fly
    # machine restarts without a volume or object storage.
    create_table :share_cards do |t|
      t.references :shared_report, null: false, index: { unique: true },
                                   foreign_key: { on_delete: :cascade }
      t.binary :png, null: false

      t.timestamps
    end
  end
end
