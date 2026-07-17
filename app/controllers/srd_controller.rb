class SrdController < ApplicationController
  def show
    @srd_html = SrdMarkdownRenderer.new(srd_markdown_path.read).to_html
  end

  private

  def srd_markdown_path
    Rails.root.join("docs/srd/atlas-srd.md")
  end
end
