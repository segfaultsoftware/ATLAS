class CelestialTransit < ApplicationRecord
  belongs_to :celestial_body, inverse_of: :celestial_transit

  validates :celestial_body_id, uniqueness: true
  validates :celestial_coordinates_start_x,
            :celestial_coordinates_start_y,
            :celestial_coordinates_target_x,
            :celestial_coordinates_target_y,
            presence: true,
            numericality: true
  validate :start_and_target_coordinates_must_differ

  private

  def start_and_target_coordinates_must_differ
    return if celestial_coordinates_start_x.nil? || celestial_coordinates_start_y.nil?
    return if celestial_coordinates_target_x.nil? || celestial_coordinates_target_y.nil?
    return unless start_coordinates == target_coordinates

    errors.add(:base, "start and target coordinates must differ")
  end

  def start_coordinates
    [ celestial_coordinates_start_x, celestial_coordinates_start_y ]
  end

  def target_coordinates
    [ celestial_coordinates_target_x, celestial_coordinates_target_y ]
  end
end
