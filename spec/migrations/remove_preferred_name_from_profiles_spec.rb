require "rails_helper"
require Rails.root.join("db/migrate/20260827000000_remove_preferred_name_from_profiles")

RSpec.describe RemovePreferredNameFromProfiles, type: :migration do
  let(:database_path) { Rails.root.join(".codex-tmp", "task-178-migration.sqlite3").to_s }

  around do |example|
    original_config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database_path)
    ActiveRecord::Base.connection.create_table(:profiles) do |table|
      table.string :preferred_name
    end
    ActiveRecord::Base.connection.execute("INSERT INTO profiles (preferred_name) VALUES ('Legacy Pilot')")

    example.run
  ensure
    ActiveRecord::Base.establish_connection(original_config)
    FileUtils.rm_f(database_path)
  end

  it "removes preferred names and recreates an empty nullable column on rollback" do
    migration = described_class.new
    profile_id = ActiveRecord::Base.connection.select_value("SELECT id FROM profiles")

    migration.migrate(:up)

    connection = ActiveRecord::Base.connection
    expect(connection.column_exists?(:profiles, :preferred_name)).to be(false)
    expect(connection.select_value("SELECT id FROM profiles")).to eq(profile_id)

    migration.migrate(:down)

    column = connection.columns(:profiles).find { |candidate| candidate.name == "preferred_name" }
    expect(column).not_to be_nil
    expect(column.null).to be(true)
    expect(connection.select_value("SELECT id FROM profiles")).to eq(profile_id)
    expect(connection.select_value("SELECT preferred_name FROM profiles")).to be_nil
  end
end
