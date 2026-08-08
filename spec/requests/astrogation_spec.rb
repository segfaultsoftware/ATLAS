require "rails_helper"

RSpec.describe "Astrogation", type: :request do
  it "renders the public scene with the shared header and all entities" do
    get "/astrogation"

    expect(response).to have_http_status(:ok)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("body > header.site-header")).to be_present
    expect(page.css("[data-astrogation-entity]").map { |entity| entity["data-name"] }).to eq(
      [ "Tejat A", "Tejat B", "Tejat C", "Ketrak Station", "Gate Alpha", "Gate Beta", "Ship" ]
    )
    expect(page.at_css("#astrogation-system")["data-astrogation-units"]).to eq("million-kilometres")
    expect(page.css("[data-astrogation-entity]").map { |entity| [ entity["data-name"], entity["data-x"], entity["data-y"] ] }).to eq(
      [
        [ "Tejat A", "140.0", "0.0" ],
        [ "Tejat B", "553.892", "534.887" ],
        [ "Tejat C", "-24.433", "1399.787" ],
        [ "Ketrak Station", "-1285.575", "-1532.089" ],
        [ "Gate Alpha", "2500.0", "0.0" ],
        [ "Gate Beta", "-2500.0", "0.0" ],
        [ "Ship", "-402.776", "520.224" ]
      ]
    )
  end

  it "renders every persisted transit through the server contract" do
    FactoryBot.create(
      :celestial_transit,
      celestial_coordinates_start_x: -24.433,
      celestial_coordinates_start_y: 1399.787,
      celestial_coordinates_target_x: -1285.575,
      celestial_coordinates_target_y: -1532.089
    )
    FactoryBot.create(
      :celestial_transit,
      celestial_coordinates_start_x: 10.0,
      celestial_coordinates_start_y: 20.0,
      celestial_coordinates_target_x: 30.0,
      celestial_coordinates_target_y: 40.0
    )

    get "/astrogation"

    expect(JSON.parse(astrogation_system["data-astrogation-transits"])).to eq(
      [
        {
          "celestial_coordinates_start" => { "x" => -24.433, "y" => 1399.787 },
          "celestial_coordinates_target" => { "x" => -1285.575, "y" => -1532.089 }
        },
        {
          "celestial_coordinates_start" => { "x" => 10.0, "y" => 20.0 },
          "celestial_coordinates_target" => { "x" => 30.0, "y" => 40.0 }
        }
      ]
    )
  end

  describe "star class selection" do
    it "defaults to the M-class catalog entry" do
      get "/astrogation"

      expect(astrogation_system["data-astrogation-star-class"]).to eq("M")
      expect(astrogation_system["data-astrogation-star-color"]).to eq("#ff6347")
      expect(astrogation_system["data-astrogation-star-brightness"]).to eq("0.8")
      expect(astrogation_star["data-star-class"]).to eq("M")
      expect(astrogation_star.at_css(".astrogation-star__core")["r"]).to eq("0.7")
    end

    it "accepts every supported class case-insensitively" do
      %w[O B A F G K M].each do |star_class|
        get "/astrogation", params: { starclass: star_class.downcase }

        expect(astrogation_system["data-astrogation-star-class"]).to eq(star_class)
        expect(astrogation_system["data-astrogation-star-color"]).to eq(
          Astrogation::StarCatalog.default.lookup(star_class)[:color]
        )
        expect(astrogation_system["data-astrogation-star-brightness"]).to eq(
          Astrogation::StarCatalog.default.lookup(star_class)[:brightness].to_s
        )
        expect(astrogation_star["data-star-class"]).to eq(star_class)
        expect(astrogation_star["data-star-color"]).to eq(
          Astrogation::StarCatalog.default.lookup(star_class)[:color]
        )
        expect(astrogation_star["data-star-brightness"]).to eq(
          Astrogation::StarCatalog.default.lookup(star_class)[:brightness].to_s
        )
        expect(astrogation_star["style"]).to include(
          "--astrogation-star-color: #{Astrogation::StarCatalog.default.lookup(star_class)[:color]};"
        )
        expect(astrogation_star["style"]).to include(
          "--astrogation-star-brightness: #{Astrogation::StarCatalog.default.lookup(star_class)[:brightness]};"
        )
        expect(astrogation_star.at_css(".astrogation-star__core")["r"]).to eq("0.7")
      end
    end

    it "exposes accessible metadata for the central star" do
      get "/astrogation", params: { starclass: "g" }

      expect(astrogation_star["aria-labelledby"]).to eq("astrogation-star-title")
      expect(astrogation_star.at_css("title").text).to eq("Central G-class star")
      expect(Nokogiri::HTML(response.body).at_css("[data-astrogation-star-description]").text)
        .to include("Central G-class star")
    end

    it "falls back to M for blank, multi-character, and unknown values" do
      [ "", "OB", "X" ].each do |starclass|
        get "/astrogation", params: { starclass: starclass }

        expect(astrogation_system["data-astrogation-star-class"]).to eq("M")
      end
    end

    it "keeps selection request-scoped and does not affect other routes" do
      system_entities = Astrogation::System.entities

      get "/astrogation", params: { starclass: "O" }
      expect(astrogation_system["data-astrogation-star-class"]).to eq("O")
      expect(Astrogation::System.entities).to equal(system_entities)

      get "/astrogation"
      expect(astrogation_system["data-astrogation-star-class"]).to eq("M")
      expect(Astrogation::System.entities).to equal(system_entities)

      get "/", params: { starclass: "O" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-astrogation-star-class")
    end
  end

  it "renders the same server contract on repeated requests" do
    get "/astrogation"
    first_body = response.body

    get "/astrogation"

    expect(response.body).to eq(first_body)
  end

  it "does not persist system state" do
    expect { get "/astrogation" }.not_to change { [ User.count, Profile.count ] }
  end

  private

  def astrogation_system
    Nokogiri::HTML(response.body).at_css("#astrogation-system")
  end

  def astrogation_star
    Nokogiri::HTML(response.body).at_css("[data-astrogation-star]")
  end
end
