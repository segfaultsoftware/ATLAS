class RemoveGoogleOauthAndResetUsers < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM profiles"
    execute "DELETE FROM users"

    remove_index :users, name: "index_users_on_provider_and_uid"
    remove_columns :users, :provider, :uid
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The destructive local-authentication reset cannot be reversed."
  end
end
