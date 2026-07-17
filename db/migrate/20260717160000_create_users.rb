class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email, null: false
      t.string :name
      t.string :remember_token
      t.datetime :remember_created_at

      t.timestamps
    end

    add_index :users, [ :provider, :uid ], unique: true
    add_index :users, :email
    add_index :users, :remember_token, unique: true
  end
end
