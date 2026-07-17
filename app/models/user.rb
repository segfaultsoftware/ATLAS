class User < ApplicationRecord
  devise :rememberable,
         :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  validates :provider, :uid, :email, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
