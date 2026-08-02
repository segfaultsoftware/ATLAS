require "rails_helper"
require "fileutils"

RSpec.describe ManualPageExporter, type: :service do
  let!(:page) do
    FactoryBot.create(
      :manual_page,
      title: "Exported Page",
      slug: "exported-page",
      content: "# Exported Page\n\nSome content.\n"
    )
  end
  let(:destination_path) { Rails.root.join(".codex-tmp", "manual-export-spec.md") }

  after do
    File.delete(destination_path) if File.exist?(destination_path)
  end

  before do
    FileUtils.mkdir_p(destination_path.dirname)
  end

  it "exports the selected page content as UTF-8 text" do
    returned_path = described_class.call(page: page, destination_path: destination_path)

    expect(returned_path.to_s).to eq(destination_path.to_s)
    expect(File.binread(destination_path)).to eq("# Exported Page\n\nSome content.\n")
  end

  it "round trips content without changing page identity" do
    described_class.call(page:, destination_path:)
    restored_page = FactoryBot.create(:manual_page, title: "Restored Page", slug: "restored-page")

    ManualPageImporter.call(page: restored_page, source_path: destination_path)

    expect(restored_page.reload).to have_attributes(
      title: "Restored Page",
      slug: "restored-page",
      content: page.content
    )
  end

  it "rejects a destination directory" do
    expect {
      described_class.call(page: page, destination_path: Rails.root.join(".codex-tmp"))
    }.to raise_error(ArgumentError, /destination file/i)
  end
end
