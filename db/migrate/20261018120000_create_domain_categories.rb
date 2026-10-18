class CreateDomainCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :domain_categories do |t|
      t.string :domain, null: false
      t.string :category, null: false
      t.string :source, null: false, default: "ai"
      t.float  :confidence

      t.timestamps
    end

    add_index :domain_categories, :domain, unique: true
  end
end
