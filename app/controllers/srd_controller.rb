class SrdController < ApplicationController
  def show
    @srd_html = SrdMarkdownRenderer.new(srd_source.read).to_html
  end

  private

  def srd_source
    Rails.root.join("docs/srd/atlas-srd.md")
  end
end
