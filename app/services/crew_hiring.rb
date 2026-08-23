class CrewHiring
  DEFAULT_STAT = 100
  STAT_INCREMENT = 10
  COST_PER_INCREMENT = 100
  STARTING_AGE_QUARTERS = 64
  TURNS_PER_QUARTER_YEAR = 1_500_000

  STAT_ATTRIBUTES = %i[max_health max_stamina max_vigor].freeze

  def self.call(game:, candidate_attributes:)
    new(game:, candidate_attributes:).call
  end

  def initialize(game:, candidate_attributes:)
    @game = game
    @candidate_attributes = candidate_attributes.to_h.symbolize_keys
  end

  def call
    pawn = build_pawn
    pawn.valid?
    add_candidate_errors(pawn)
    return pawn if pawn.errors.any?

    persist(pawn)
    pawn
  end

  private

  attr_reader :game, :candidate_attributes

  def build_pawn
    game.pawns.build(
      first_name: candidate_attributes[:first_name],
      nickname: candidate_attributes[:nickname],
      last_name: candidate_attributes[:last_name],
      born_on_turn: derived_born_on_turn,
      max_health: parsed_stats[:max_health],
      current_health: parsed_stats[:max_health],
      max_stamina: parsed_stats[:max_stamina],
      current_stamina: parsed_stats[:max_stamina],
      max_vigor: parsed_stats[:max_vigor],
      current_vigor: parsed_stats[:max_vigor]
    )
  end

  def add_candidate_errors(pawn)
    STAT_ATTRIBUTES.each do |attribute|
      value = parsed_stats[attribute]
      next if value && value >= DEFAULT_STAT && (value - DEFAULT_STAT).remainder(STAT_INCREMENT).zero?

      pawn.errors.add(attribute, "must be an integer increment of 10 from 100")
    end
    pawn.errors.add(:starting_budget, "must be an integer") unless parsed_starting_budget
  end

  def persist(pawn)
    GameInitialization.transaction do
      initialization = GameInitialization.lock.find_by(game_id: game.id)
      unless initialization
        pawn.errors.add(:base, "Game initialization is required")
        raise ActiveRecord::Rollback
      end

      unless initialization.remaining_budget == parsed_starting_budget
        pawn.errors.add(:starting_budget, "does not match the current remaining budget")
        raise ActiveRecord::Rollback
      end

      resulting_budget = initialization.remaining_budget - derived_cost
      if resulting_budget.negative?
        pawn.errors.add(:base, "Remaining budget cannot be negative")
        raise ActiveRecord::Rollback
      end

      pawn.save!
      initialization.update!(remaining_budget: resulting_budget)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => error
    pawn.errors.add(:base, error.message) if pawn.errors.empty?
  end

  def parsed_stats
    @parsed_stats ||= STAT_ATTRIBUTES.to_h do |attribute|
      [ attribute, parse_integer(candidate_attributes[attribute]) ]
    end
  end

  def parsed_starting_budget
    @parsed_starting_budget ||= parse_integer(candidate_attributes[:starting_budget])
  end

  def derived_cost
    increment_count * COST_PER_INCREMENT
  end

  def derived_born_on_turn
    -(STARTING_AGE_QUARTERS + increment_count) * TURNS_PER_QUARTER_YEAR
  end

  def increment_count
    return 0 unless parsed_stats.values.all?

    parsed_stats.values.sum { |value| (value - DEFAULT_STAT) / STAT_INCREMENT }
  end

  def parse_integer(value)
    return value if value.is_a?(Integer)
    return unless value.is_a?(String) && value.match?(/\A-?\d+\z/)

    value.to_i
  end
end
