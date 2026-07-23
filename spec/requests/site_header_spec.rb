require "rails_helper"

RSpec.describe "Site header", type: :request do
  def application_css
    Rails.root.join("app/assets/stylesheets/application.css").read
  end

  it "renders a shared public header with home branding and one auth control" do
    [ "/", "/srd", "/srd/", "/status" ].each do |path|
      get path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      header = page.at_css("body > header.site-header")
      brand = header.at_css('a.site-brand[href="/"]')
      auth_forms = header.css('form[action="/users/auth/google_oauth2"]')

      expect(brand.at_css('.site-brand__mark[aria-hidden="true"]')).to be_present
      expect(brand.at_css(".pixel-spaceship")).to be_present
      expect(brand.at_css(".site-brand__text").text).to eq("ATLAS")
      expect(auth_forms.size).to eq(1)
      expect(auth_forms.first["method"]).to eq("post")
      expect(auth_forms.first["data-turbo"]).to eq("false")
      expect(auth_forms.css("button").map(&:text).map(&:strip)).to contain_exactly("Login/Register")
      expect(response.body).not_to include("/users/sign_in")
      expect(response.body).not_to include("/users/sign_up")
      expect(page.at_css(".account-menu")).to be_nil
    end
  end

  it "keeps the public header in normal page flow" do
    site_header_css = application_css[/\.site-header \{[^}]+\}/]
    site_navigation_css = application_css[/\.site-navigation \{[^}]+\}/]

    expect(site_header_css).not_to include("position: fixed")
    expect(site_header_css).not_to include("position: sticky")
    expect(site_navigation_css).to include("display: flex;")
    expect(site_navigation_css).not_to include("position: fixed")
    expect(site_navigation_css).not_to include("position: sticky")
  end
end
