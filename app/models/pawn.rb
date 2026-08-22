class Pawn < ApplicationRecord
  STAT_ATTRIBUTES = %i[
    max_health
    current_health
    max_stamina
    current_stamina
    max_vigor
    current_vigor
  ].freeze

  belongs_to :game, inverse_of: :pawns

  before_validation :normalize_names

  validates :first_name, presence: true, length: { maximum: 18 }
  validates :nickname, presence: true, length: { maximum: 18 }
  validates :last_name, length: { maximum: 18 }, allow_nil: true
  validates :born_on_turn, numericality: { only_integer: true }
  validates(*STAT_ATTRIBUTES,
            numericality: { only_integer: true, greater_than: 0 })

  private

  def normalize_names
    self.first_name = first_name&.strip
    self.nickname = nickname&.strip
    self.last_name = last_name&.strip
    self.nickname = first_name if nickname.blank?
  end
end
