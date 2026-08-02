require "rails_helper"

RSpec.describe SrdMarkdownRenderer do
  it "sanitizes rendered Markdown HTML" do
    html = described_class.new("# Title\n\n<script>alert('x')</script>\n\n**Safe text**").to_html

    expect(html).to include('<h1 id="title">Title')
    expect(html).to include("<strong>Safe text</strong>")
    expect(html).not_to include("<script")
  end

  it "provides heading anchors for the table of contents" do
    renderer = described_class.new("# Title\n\n## Details & More\n\n## Details & More")

    expect(renderer.table_of_contents).to eq(
      [
        { level: 1, text: "Title", id: "title" },
        { level: 2, text: "Details & More", id: "details--more" },
        { level: 2, text: "Details & More", id: "details--more-1" }
      ]
    )
    expect(renderer.to_html).to include('id="details--more"')
    expect(renderer.to_html).to include('id="details--more-1"')
  end
end
