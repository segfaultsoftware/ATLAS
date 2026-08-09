require "rails_helper"
require Rails.root.join("db/migrate/20260809000100_remove_google_oauth_and_reset_users")

RSpec.describe RemoveGoogleOauthAndResetUsers, type: :migration do
  let(:database_path) { Rails.root.join(".codex-tmp", "task-116-migration.sqlite3").to_s }

  around do |example|
    original_config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database_path)
    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = ON")
    create_legacy_schema

    example.run
  ensure
    ActiveRecord::Base.establish_connection(original_config)
    FileUtils.rm_f(database_path)
  end

  def create_legacy_schema
    connection = ActiveRecord::Base.connection
    connection.create_table(:users) do |table|
      table.string :provider, null: false
      table.string :uid, null: false
      table.string :email, null: false
      table.string :encrypted_password, null: false, default: ""
      table.timestamps
    end
    connection.add_index :users, [ :provider, :uid ], unique: true, name: "index_users_on_provider_and_uid"
    connection.create_table(:profiles) do |table|
      table.references :user, null: false
      table.string :preferred_name
      table.timestamps
    end
    connection.add_foreign_key :profiles, :users
    connection.execute("INSERT INTO users (provider, uid, email, encrypted_password, created_at, updated_at) VALUES ('google_oauth2', 'legacy-1', 'legacy@example.com', '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
    connection.execute("INSERT INTO profiles (user_id, preferred_name, created_at, updated_at) VALUES (1, 'Legacy Pilot', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
  end

  it "deletes profiles before users and removes the OAuth schema" do
    described_class.new.migrate(:up)

    connection = ActiveRecord::Base.connection
    expect(connection.select_value("SELECT COUNT(*) FROM profiles").to_i).to eq(0)
    expect(connection.select_value("SELECT COUNT(*) FROM users").to_i).to eq(0)
    expect(connection.column_exists?(:users, :provider)).to be(false)
    expect(connection.column_exists?(:users, :uid)).to be(false)
    expect(connection.indexes(:users).map(&:name)).not_to include("index_users_on_provider_and_uid")
    expect(connection.column_exists?(:users, :encrypted_password)).to be(true)
  end

  it "is irreversible" do
    expect { described_class.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
