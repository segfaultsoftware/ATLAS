require "rails_helper"
require "fileutils"

RSpec.describe ManualPageImporter, type: :service do
  let!(:page) do
    FactoryBot.create(
      :manual_page,
      title: "Existing Page",
      slug: "existing-page",
      content: "Original content"
    )
  end
  let(:source_path) { Rails.root.join(".codex-tmp", "manual-import-spec.md") }

  before do
    FileUtils.mkdir_p(source_path.dirname)
    File.binwrite(source_path, "# Updated content\n\nImported from a file.\n")
  end

  after do
    File.delete(source_path) if File.exist?(source_path)
  end

  it "imports UTF-8 content into the selected page without changing its identity" do
    imported_page = described_class.call(page: page, source_path: source_path)

    expect(imported_page).to eq(page)
    expect(page.reload).to have_attributes(
      title: "Existing Page",
      slug: "existing-page",
      content: "# Updated content\n\nImported from a file.\n"
    )
  end

  it "rejects missing source files" do
    missing_path = Rails.root.join(".codex-tmp", "missing.md")

    expect {
      described_class.call(page: page, source_path: missing_path)
    }.to raise_error(ArgumentError, /source file/i)
  end

  it "rejects invalid UTF-8 source files" do
    File.binwrite(source_path, "invalid\xff")

    expect {
      described_class.call(page: page, source_path: source_path)
    }.to raise_error(ArgumentError, /UTF-8/i)
  end
end
