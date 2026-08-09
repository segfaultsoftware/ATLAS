class User < ApplicationRecord
  has_one :profile, dependent: :destroy, inverse_of: :user, autosave: true

  enum :role, { user: "user", webadmin: "webadmin" }, default: :user

  attr_accessor :preferred_name

  devise :database_authenticatable,
         :registerable,
         :rememberable,
         :validatable

  validates :preferred_name, presence: true, on: :create

  def ensure_profile!(preferred_name:)
    with_lock do
      profile || create_profile!(preferred_name: preferred_name.presence)
    end
  end
end
