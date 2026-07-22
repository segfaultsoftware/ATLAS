class Profile < ApplicationRecord
  AVATAR_OPTIONS = {
    "smile" => "🙂",
    "frown" => "🙁",
    "cry" => "😢"
  }.freeze
  DEFAULT_AVATAR_KEY = "smile"

  belongs_to :user

  before_validation :set_default_avatar_key

  validates :user_id, uniqueness: true
  validates :preferred_playtimes, length: { maximum: 256 }, allow_blank: true
  validates :avatar_key, inclusion: { in: AVATAR_OPTIONS.keys }

  def self.avatar_options
    AVATAR_OPTIONS
  end

  def avatar_emoji
    AVATAR_OPTIONS.fetch(avatar_key.presence || DEFAULT_AVATAR_KEY)
  end

  private

  def set_default_avatar_key
    self.avatar_key = DEFAULT_AVATAR_KEY if avatar_key.blank?
  end
end
