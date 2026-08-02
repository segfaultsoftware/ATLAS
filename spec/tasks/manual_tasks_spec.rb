require "rails_helper"
require "rake"
require "fileutils"

load Rails.root.join("lib/tasks/manual.rake")
Rake::Task.define_task(:environment)

RSpec.describe "Manual maintenance tasks", type: :task do
  let!(:page) { FactoryBot.create(:manual_page, slug: "task-page", content: "Before") }
  let(:source_path) { Rails.root.join(".codex-tmp", "manual-task-source.md") }
  let(:destination_path) { Rails.root.join(".codex-tmp", "manual-task-destination.md") }

  before do
    FileUtils.mkdir_p(source_path.dirname)
    File.binwrite(source_path, "After")
  end

  after do
    [ source_path, destination_path ].each do |path|
      File.delete(path) if File.exist?(path)
    end
    [ "manual:import", "manual:export" ].each do |task_name|
      Rake::Task[task_name].reenable
    end
  end

  it "imports page content through the import task" do
    Rake::Task["manual:import"].invoke(page.slug, source_path.to_s)

    expect(page.reload.content).to eq("After")
  end

  it "exports page content through the export task" do
    Rake::Task["manual:export"].invoke(page.slug, destination_path.to_s)

    expect(File.binread(destination_path)).to eq("Before")
  end
end
