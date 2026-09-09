# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  respond_to :json

  private

  # Registration only delivers a code. No token is issued until the OTP is
  # verified, so Warden is never involved here.
  def sign_up(_resource_name, resource)
    resource.deliver_otp!
  end

  # Devise's default reads the session, which an api_only app does not have.
  def after_sign_up_path_for(_resource)
    nil
  end

  def respond_with(resource, _opts = {})
    if resource.persisted?
      render json: {
        message: "Signed up. Check your email for a verification code.",
        email: resource.email,
        otp_required: true
      }, status: :created
    else
      render json: { errors: resource.errors.full_messages }, status: :unprocessable_content
    end
  end
end
