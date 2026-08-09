class User < ApplicationRecord
  has_one :profile, dependent: :destroy, inverse_of: :user, autosave: true

  enum :role, { user: "user", webadmin: "webadmin" }, default: :user

  attr_accessor :preferred_name

  devise :database_authenticatable,
         :registerable,
         :rememberable,
         :omniauthable,
         :validatable,
         omniauth_providers: [ :google_oauth2 ]

  validates :preferred_name, presence: true, on: :create
  validates :uid, uniqueness: { scope: :provider }, allow_blank: true

  def self.find_or_create_from_google_oauth!(auth)
    transaction do
      find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
        user.email = auth.info.email
        user.name = auth.info.name
        user.preferred_name = auth.info.name
        if user.encrypted_password.blank?
          user.password = Devise.friendly_token(32)
          user.password_confirmation = user.password
        end
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
