module Webadmin
  class ManualPagesController < BaseController
    before_action :set_manual_page, only: [ :edit, :update ]

    def index
      @manual_pages = ManualPage.order(:title)
    end

    def new
      @manual_page = ManualPage.new
    end

    def create
      @manual_page = ManualPage.new(manual_page_params)

      if @manual_page.save
        redirect_to edit_webadmin_manual_page_path(id: @manual_page.id), notice: "Manual page saved."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @manual_page.update(manual_page_params)
        redirect_to edit_webadmin_manual_page_path(id: @manual_page.id), notice: "Manual page saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def preview
      @manual_page = ManualPage.new(manual_page_params)
      @preview_html = SrdMarkdownRenderer.new(@manual_page.content).to_html
    end

    private

    def set_manual_page
      @manual_page = ManualPage.find(params[:id])
    end

    def manual_page_params
      params.require(:manual_page).permit(:title, :slug, :content, :parent_id)
    end
  end
end
