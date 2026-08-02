class User < ApplicationRecord
  has_one :profile, dependent: :destroy

  enum :role, { user: "user", webadmin: "webadmin" }, default: :user

  devise :rememberable,
         :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  validates :provider, :uid, :email, presence: true
  validates :uid, uniqueness: { scope: :provider }

  def self.find_or_create_from_google_oauth!(auth)
    transaction do
      find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
        user.email = auth.info.email
        user.name = auth.info.name
        user.save!
        user.ensure_profile!(preferred_name: auth.info.name)
      end
    end
  end

  def ensure_profile!(preferred_name:)
    with_lock do
      profile || create_profile!(preferred_name: preferred_name.presence)
    end
  end
end
