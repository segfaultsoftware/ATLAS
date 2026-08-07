require "yaml"

module Astrogation
  class StarCatalog
    SUPPORTED_CLASSES = %w[O B A F G K M].map(&:freeze).freeze
    DEFAULT_CLASS = "M".freeze
    CATALOG_PATH = Rails.root.join("config/astrogation/star_classes.yml").freeze
    COLOR_PATTERN = /\A#[0-9a-fA-F]{6}\z/.freeze

    class ConfigurationError < StandardError; end

    class << self
      def lookup(star_class)
        default.lookup(star_class)
      end

      def normalize(star_class)
        default.normalize(star_class)
      end

      def default
        @default ||= new
      end
    end

    def initialize(path: CATALOG_PATH)
      @entries = load_entries(path)
    end

    def entries
      @entries
    end

    def lookup(star_class)
      unless SUPPORTED_CLASSES.include?(star_class)
        raise ConfigurationError, "Unsupported stellar class: #{star_class.inspect}"
      end

      @entries.fetch(star_class)
    end

    def normalize(star_class)
      normalized = star_class.strip.upcase if star_class.is_a?(String)
      SUPPORTED_CLASSES.include?(normalized) ? normalized : DEFAULT_CLASS
    end

    private

    def load_entries(path)
      raw_catalog = load_yaml(path)
      validate_catalog_shape!(raw_catalog, path)

      entries = SUPPORTED_CLASSES.each_with_object({}) do |star_class, catalog|
        properties = raw_catalog.fetch(star_class)
        validate_properties!(properties, star_class, path)

        catalog[star_class] = {
          color: properties.fetch("color").dup.freeze,
          brightness: properties.fetch("brightness")
        }.freeze
      end

      entries.freeze
    end

    def load_yaml(path)
      YAML.safe_load(File.read(path), aliases: false)
    rescue Psych::Exception, SystemCallError => error
      raise ConfigurationError, "Star catalog could not be loaded from #{path}: #{error.message}"
    end

    def validate_catalog_shape!(raw_catalog, path)
      unless raw_catalog.is_a?(Hash)
        raise ConfigurationError, "Star catalog at #{path} must contain a class mapping"
      end

      unsupported_classes = raw_catalog.keys - SUPPORTED_CLASSES
      unless unsupported_classes.empty?
        raise ConfigurationError, "Star catalog at #{path} contains unsupported stellar class #{unsupported_classes.first.inspect}"
      end

      missing_class = SUPPORTED_CLASSES.find { |star_class| !raw_catalog.key?(star_class) }
      if missing_class
        raise ConfigurationError, "Star catalog at #{path} is missing stellar class #{missing_class}"
      end
    end

    def validate_properties!(properties, star_class, path)
      unless properties.is_a?(Hash) && properties.key?("color") && properties.key?("brightness")
        raise ConfigurationError, "Star catalog at #{path} has missing color or brightness for stellar class #{star_class}"
      end

      color = properties.fetch("color")
      unless color.is_a?(String) && COLOR_PATTERN.match?(color)
        raise ConfigurationError, "Star catalog at #{path} has invalid color for stellar class #{star_class}"
      end

      brightness = properties.fetch("brightness")
      unless brightness.is_a?(Numeric) && brightness.respond_to?(:finite?) && brightness.finite? && brightness.positive?
        raise ConfigurationError, "Star catalog at #{path} has invalid brightness for stellar class #{star_class}"
      end
    end
  end
end
