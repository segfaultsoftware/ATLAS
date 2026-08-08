class CelestialTransit < ApplicationRecord
  belongs_to :celestial_body, inverse_of: :celestial_transit

  validates :celestial_body_id, uniqueness: true
  validates :celestial_coordinates_start, :celestial_coordinates_target, presence: true
  validate :coordinates_must_differ

  private

  def coordinates_must_differ
    return if celestial_coordinates_start.blank? || celestial_coordinates_target.blank?

    return unless normalized_coordinates(celestial_coordinates_start) == normalized_coordinates(celestial_coordinates_target)

    errors.add(:celestial_coordinates_target, :equal_to_start)
  end

  def normalized_coordinates(coordinates)
    return coordinates unless coordinates.respond_to?(:to_h)

    coordinates.to_h.transform_keys(&:to_s)
  end
end
