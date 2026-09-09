# frozen_string_literal: true

class OtpController < ApplicationController
  # POST /otp/verify
  # The second factor. This is the only path configured to dispatch a JWT.
  def verify
    user = User.find_by(email: normalized_email)

    if user&.verify_otp(otp_params[:code])
      # store: false keeps Warden out of the (nonexistent) session. The
      # after_set_user hook still fires, and that is what issues the token.
      sign_in(user, store: false)

      render json: { user: user.slice(:id, :email) }, status: :ok
    else
      render json: { error: "Invalid or expired code." }, status: :unauthorized
    end
  end

  # POST /otp/resend
  def resend
    User.find_by(email: normalized_email)&.deliver_otp!

    # Deliberately identical whether or not the account exists, so this cannot
    # be used to enumerate registered emails.
    render json: { message: "If that account exists, a new code has been sent." }, status: :accepted
  end

  private

  def otp_params
    params.permit(:email, :code)
  end

  def normalized_email
    otp_params[:email].to_s.strip.downcase
  end
end
