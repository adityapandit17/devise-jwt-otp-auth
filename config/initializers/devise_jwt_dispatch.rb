# frozen_string_literal: true

# devise-jwt derives its dispatch paths from the Devise routes and pushes them
# onto the configured list in an after_initialize hook, which would hand out a
# token at POST /login and POST /signup. That would defeat the second factor,
# so the list is replaced here with the OTP verification path alone.
#
# This runs after the gem's own hook because app initializers are registered
# later than railtie initializers.
Rails.application.config.after_initialize do
  Warden::JWTAuth.configure do |config|
    config.dispatch_requests = [
      [ "POST", %r{^/otp/verify$} ]
    ]
  end
end
