class User < ApplicationRecord
  has_one :profile, dependent: :destroy, inverse_of: :user, autosave: true

  enum :role, { user: "user", webadmin: "webadmin" }, default: :user

  devise :database_authenticatable,
         :registerable,
         :rememberable,
         :validatable

  validates :password_confirmation, presence: true, on: :create

  def ensure_profile!
    with_lock do
      profile || create_profile!
    end
  end
end
