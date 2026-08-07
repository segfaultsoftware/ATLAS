require "rails_helper"
require "tempfile"

RSpec.describe Astrogation::StarCatalog, type: :service do
  let(:catalog_path) { Rails.root.join("config/astrogation/star_classes.yml") }
  let(:catalog) { described_class.new(path: catalog_path) }

  describe "the configured catalog" do
    it "contains the seven supported classes with color and brightness" do
      expect(catalog.entries.keys).to eq(%w[O B A F G K M])
      expect(catalog.entries.values).to all(include(:color, :brightness))
      expect(catalog.entries.values.map { |entry| entry[:color] }).to all(match(/\A#[0-9A-Fa-f]{6}\z/))
      expect(catalog.entries.values.map { |entry| entry[:brightness] }).to all(be_a(Numeric).and be > 0)
    end

    it "returns immutable catalog data" do
      expect(catalog.entries).to be_frozen
      expect(catalog.entries.values).to all(be_frozen)
      expect(catalog.entries.values.map { |entry| entry[:color] }).to all(be_frozen)

      expect { catalog.lookup("O")[:color].replace("#000000") }.to raise_error(FrozenError)
      expect { catalog.entries.delete("O") }.to raise_error(FrozenError)
    end
  end

  describe "#lookup" do
    it "returns the requested canonical class properties" do
      expect(catalog.lookup("G")).to eq(color: "#fff4c2", brightness: 1.2)
    end

    it "raises a configuration error for an unsupported internal class" do
      expect { catalog.lookup("X") }
        .to raise_error(described_class::ConfigurationError, /unsupported stellar class/i)
    end
  end

  describe "#normalize" do
    it "normalizes supported values case-insensitively" do
      expect(catalog.normalize("o")).to eq("O")
      expect(catalog.normalize(" m ")).to eq("M")
    end

    it "falls back to M for missing, blank, non-string, and unknown values" do
      expect(catalog.normalize(nil)).to eq("M")
      expect(catalog.normalize(" ")).to eq("M")
      expect(catalog.normalize(123)).to eq("M")
      expect(catalog.normalize("OB")).to eq("M")
      expect(catalog.normalize("X")).to eq("M")
    end
  end

  describe "configuration validation" do
    it "fails clearly for malformed YAML" do
      with_catalog("O: [") do |path|
        expect { described_class.new(path: path) }
          .to raise_error(described_class::ConfigurationError, /could not be loaded/i)
      end
    end

    it "fails clearly when a supported class is missing" do
      with_catalog(valid_catalog_yaml.sub(/M:\n  color: '#ff6347'\n  brightness: 0\.8\n\z/, "")) do |path|
        expect { described_class.new(path: path) }
          .to raise_error(described_class::ConfigurationError, /missing stellar class M/i)
      end
    end

    it "fails clearly when a required property is missing" do
      with_catalog(valid_catalog_yaml.sub("brightness: 1.2", "")) do |path|
        expect { described_class.new(path: path) }
          .to raise_error(described_class::ConfigurationError, /missing color or brightness/i)
      end
    end

    it "fails clearly for an unsafe color" do
      with_catalog(valid_catalog_yaml.sub("#fff4c2", "red; fill: blue")) do |path|
        expect { described_class.new(path: path) }
          .to raise_error(described_class::ConfigurationError, /invalid color/i)
      end
    end

    it "fails clearly for a non-positive, non-finite, or non-numeric brightness" do
      [ "0", ".nan", "bright" ].each do |brightness|
        with_catalog(valid_catalog_yaml.sub("brightness: 1.2", "brightness: #{brightness}")) do |path|
          expect { described_class.new(path: path) }
            .to raise_error(described_class::ConfigurationError, /invalid brightness/i)
        end
      end
    end
  end

  private

  def valid_catalog_yaml
    <<~YAML
      O:
        color: '#9bbcff'
        brightness: 1.8
      B:
        color: '#b9d7ff'
        brightness: 1.6
      A:
        color: '#f8f7ff'
        brightness: 1.4
      F:
        color: '#fff4ea'
        brightness: 1.3
      G:
        color: '#fff4c2'
        brightness: 1.2
      K:
        color: '#ffd2a1'
        brightness: 1.0
      M:
        color: '#ff6347'
        brightness: 0.8
    YAML
  end

  def with_catalog(contents)
    Tempfile.create([ "star-classes", ".yml" ]) do |file|
      file.write(contents)
      file.flush
      yield Pathname.new(file.path)
    end
  end
end
