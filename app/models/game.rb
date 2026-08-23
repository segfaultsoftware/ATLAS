class Game < ApplicationRecord
  MAX_GAMES_PER_PROFILE = 5
  RANDOMIZATION_SEED_UPPER_BOUND = 2**32

  belongs_to :profile, inverse_of: :games
  has_one :game_initialization,
          dependent: :destroy,
          inverse_of: :game,
          autosave: true
  has_many :pawns, dependent: :destroy, inverse_of: :game

  attr_readonly :randomization_seed

  before_validation :build_default_game_initialization, on: :create
  before_validation :normalize_name
  before_validation :set_randomization_seed, on: :create

  validates :name, presence: true, length: { maximum: 64 }
  validates :randomization_seed,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than: RANDOMIZATION_SEED_UPPER_BOUND
            }
  validate :profile_has_capacity, on: :create

  private

  def build_default_game_initialization
    build_game_initialization unless game_initialization
  end

  def normalize_name
    self.name = name&.strip
  end

  def set_randomization_seed
    @system_randomization_seed ||= SecureRandom.random_number(RANDOMIZATION_SEED_UPPER_BOUND)
    self.randomization_seed = @system_randomization_seed
  end

  def profile_has_capacity
    return if profile_id.blank?
    return if self.class.where(profile_id: profile_id).count < MAX_GAMES_PER_PROFILE

    errors.add(:base, "A profile can have at most #{MAX_GAMES_PER_PROFILE} games")
  end
end
