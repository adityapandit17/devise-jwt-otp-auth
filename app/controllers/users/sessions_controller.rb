# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  respond_to :json

  # POST /login
  # Only the first factor. A valid password earns an emailed code, not a token.
  def create
    self.resource = warden.authenticate!(auth_options)
    resource.deliver_otp!

    render json: {
      message: "Password accepted. Check your email for a verification code.",
      email: resource.email,
      otp_required: true
    }, status: :ok
  end

  private

  def respond_to_on_destroy
    head :no_content
  end
end
