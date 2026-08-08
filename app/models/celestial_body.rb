class CelestialBody < ApplicationRecord
  has_one :celestial_transit, dependent: :destroy, inverse_of: :celestial_body

  validates :name, presence: true, uniqueness: true
end
