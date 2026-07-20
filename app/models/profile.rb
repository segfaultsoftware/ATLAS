class Profile < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
  validates :preferred_playtimes, length: { maximum: 256 }, allow_blank: true
end
