class OtpMailer < ApplicationMailer
  def code(user, code)
    @code = code
    @validity_minutes = (User::OTP_VALIDITY / 60).to_i

    mail(to: user.email, subject: "Your verification code")
  end
end
