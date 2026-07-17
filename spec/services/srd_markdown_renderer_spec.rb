require "rails_helper"

RSpec.describe SrdMarkdownRenderer do
  it "sanitizes rendered Markdown HTML" do
    html = described_class.new("# Title\n\n<script>alert('x')</script>\n\n**Safe text**").to_html

    expect(html).to include("<h1>Title")
    expect(html).to include("<strong>Safe text</strong>")
    expect(html).not_to include("<script")
  end
end
