# frozen_string_literal: true

Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = "no-reply@atlas.local"
  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth ]
  config.stretches = Rails.env.test? ? 1 : 12

  config.remember_for = 1.month
  config.expire_all_remember_me_on_sign_out = true

  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  config.omniauth :google_oauth2,
                  ENV.fetch("GOOGLE_OAUTH_CLIENT_ID", nil),
                  ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET", nil),
                  scope: "email,profile",
                  prompt: "select_account"
end
