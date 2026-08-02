class ManualController < ApplicationController
  skip_before_action :require_authenticated_user!

  before_action :load_manual_page, only: :show

  def index
    redirect_to manual_page_path(Rails.configuration.x.manual.landing_page_slug)
  end

  def show
    renderer = SrdMarkdownRenderer.new(@manual_page.content)
    @manual_html = renderer.to_html
    @table_of_contents = renderer.table_of_contents
    @breadcrumbs = @manual_page.ancestors
    @categories = @manual_page.categories.order(:name)
    @page_flow = page_flow
    @latest_pages = ManualPage.order(updated_at: :desc, id: :desc).limit(5)
  end

  private

  def load_manual_page
    @manual_page = ManualPage.find_by!(slug: params[:slug])
  end

  def page_flow
    pages = sibling_pages.to_a
    current_index = pages.index(@manual_page)

    {
      previous: current_index && current_index.positive? ? pages[current_index - 1] : nil,
      next: current_index && pages[current_index + 1]
    }
  end

  def sibling_pages
    scope = if @manual_page.parent
      @manual_page.parent.children
    else
      ManualPage.where(parent_id: nil)
    end

    scope.order(:created_at, :id)
  end
end
