require "cgi"
require "commonmarker"

class SrdMarkdownRenderer
  ALLOWED_ATTRIBUTES = %w[href id title].freeze
  ALLOWED_TAGS = %w[
    a blockquote br code em h1 h2 h3 h4 h5 h6 hr li ol p pre strong
    table tbody td th thead tr ul
  ].freeze

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  def to_html
    sanitize(rendered_markdown_html).html_safe
  end

  def table_of_contents
    rendered_markdown_html
    @table_of_contents
  end

  private

  attr_reader :markdown

  def rendered_markdown_html
    return @rendered_markdown_html if defined?(@rendered_markdown_html)

    @rendered_markdown_html = render_unsanitized_markdown_html
    @table_of_contents = @rendered_markdown_html.scan(/<h([1-6])\s+id="([^"]+)">(.*?)<\/h\1>/m).map do |level, heading_id, inner_html|
      heading_text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(inner_html))

      { level: level.to_i, text: heading_text, id: heading_id }
    end

    @rendered_markdown_html
  end

  def render_unsanitized_markdown_html
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
