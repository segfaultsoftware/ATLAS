class CreateManualCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :manual_categories, :slug, unique: true
  end
end
