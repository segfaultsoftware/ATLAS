class RemovePreferredNameFromProfiles < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE profiles DROP COLUMN preferred_name"
  end

  def down
    add_column :profiles, :preferred_name, :string
  end
end
