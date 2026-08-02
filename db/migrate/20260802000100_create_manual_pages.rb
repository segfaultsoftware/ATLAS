class CreateManualPages < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_pages do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :content, null: false, default: ""
      t.references :parent, foreign_key: { to_table: :manual_pages }

      t.timestamps
    end

    add_index :manual_pages, :slug, unique: true
  end
end
