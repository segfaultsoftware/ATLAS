class CreateManualPageCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_page_categories do |t|
      t.references :manual_page, null: false, foreign_key: true
      t.references :manual_category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :manual_page_categories,
              [ :manual_page_id, :manual_category_id ],
              unique: true,
              name: "index_manual_page_categories_on_page_and_category"
  end
end
