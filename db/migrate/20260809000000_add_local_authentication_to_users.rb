class AddLocalAuthenticationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :encrypted_password, :string, null: false, default: ""

    change_column_null :users, :provider, true
    change_column_null :users, :uid, true

    remove_index :users, :email
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"
  end
end
