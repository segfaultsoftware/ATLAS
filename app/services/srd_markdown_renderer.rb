require "commonmarker"

class SrdMarkdownRenderer
  ALLOWED_ATTRIBUTES = %w[href title].freeze
  ALLOWED_TAGS = %w[
    a blockquote br code em h1 h2 h3 h4 h5 h6 hr li ol p pre strong
    table tbody td th thead tr ul
  ].freeze

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  def to_html
    sanitize(render_markdown).html_safe
  end

  private

  attr_reader :markdown

  def render_markdown
    Commonmarker.to_html(
      markdown,
      options: {
        extension: { tagfilter: false },
        parse: { smart: true },
        render: { unsafe: true }
      }
    )
  end

  def sanitize(html)
    ActionController::Base.helpers.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    )
  end
end
