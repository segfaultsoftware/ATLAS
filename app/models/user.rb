class User < ApplicationRecord
  has_one :profile, dependent: :destroy

  devise :rememberable,
         :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  validates :provider, :uid, :email, presence: true
  validates :uid, uniqueness: { scope: :provider }

  def self.find_or_create_from_google_oauth!(auth)
    find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
      user.email = auth.info.email
      user.name = auth.info.name
      user.save!
    end
  end
end
