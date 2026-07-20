class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :preferred_name
      t.string :pronouns
      t.string :preferred_playtimes, limit: 256
      t.string :avatar_key

      t.timestamps
    end
  end
end
