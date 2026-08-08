module Astrogation
  module System
    DISTANCE_UNIT = "million-kilometres".freeze
    SHIP_INTERPOLATION_RATIO = 0.3

    ENTITY_DEFINITIONS = [
      { name: "Tejat A", kind: "planet", distance_mkm: 140.0, angle_degrees: 0.0 },
      { name: "Tejat B", kind: "planet", distance_mkm: 770.0, angle_degrees: 44.0 },
      { name: "Tejat C", kind: "planet", distance_mkm: 1400.0, angle_degrees: 91.0 },
      { name: "Ketrak Station", kind: "station", distance_mkm: 2000.0, angle_degrees: 230.0 },
      { name: "Gate Alpha", kind: "gate", distance_mkm: 2500.0, angle_degrees: 0.0 },
      { name: "Gate Beta", kind: "gate", distance_mkm: 2500.0, angle_degrees: 180.0 }
    ].map(&:freeze).freeze

    module_function

    def entities
      @entities ||= begin
        positioned_entities = ENTITY_DEFINITIONS.map do |definition|
          definition.merge(coordinate(distance: definition.fetch(:distance_mkm), angle: definition.fetch(:angle_degrees))).freeze
        end

        ship = ship_entity(
          origin: positioned_entities.fetch(2),
          destination: positioned_entities.fetch(3)
        )

        (positioned_entities + [ ship ]).freeze
      end
    end

    def transits
      CelestialTransit.order(:id).map do |transit|
        start_coordinates = {
          x: transit.celestial_coordinates_start_x.to_f,
          y: transit.celestial_coordinates_start_y.to_f
        }.freeze
        target_coordinates = {
          x: transit.celestial_coordinates_target_x.to_f,
          y: transit.celestial_coordinates_target_y.to_f
        }.freeze

        {
          celestial_coordinates_start: start_coordinates,
          celestial_coordinates_target: target_coordinates
        }.freeze
      end.freeze
    end

    def coordinate(distance:, angle:)
      radians = angle * Math::PI / 180

      {
        x: (distance * Math.cos(radians)).round(3).to_f,
        y: (distance * Math.sin(radians)).round(3).to_f
      }
    end

    def ship_entity(origin:, destination:)
      position = interpolate_position(origin: origin, destination: destination, ratio: SHIP_INTERPOLATION_RATIO)

      {
        name: "Ship",
        kind: "ship",
        x: position.fetch(:x),
        y: position.fetch(:y)
      }.freeze
    end

    def interpolate_position(origin:, destination:, ratio:)
      {
        x: (origin.fetch(:x) + (destination.fetch(:x) - origin.fetch(:x)) * ratio).round(3).to_f,
        y: (origin.fetch(:y) + (destination.fetch(:y) - origin.fetch(:y)) * ratio).round(3).to_f
      }
    end
  end
end
