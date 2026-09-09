class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  OTP_LENGTH = 6
  OTP_VALIDITY = 10.minutes
  MAX_OTP_ATTEMPTS = 5

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  # Delivered inline so the code is in the inbox before the response returns.
  # Move to deliver_later once a queue worker runs in production.
  def deliver_otp!
    OtpMailer.code(self, generate_otp!).deliver_now
  end

  # Issues a fresh code and returns it in plain text. Only the digest is
  # persisted, so this return value is the only chance to deliver it.
  def generate_otp!
    code = format("%0#{OTP_LENGTH}d", SecureRandom.random_number(10**OTP_LENGTH))

    update!(
      otp_code_digest: BCrypt::Password.create(code),
      otp_expires_at: OTP_VALIDITY.from_now,
      otp_attempts: 0
    )

    code
  end

  def verify_otp(code)
    return false if otp_code_digest.blank? || otp_expired? || otp_locked?

    if BCrypt::Password.new(otp_code_digest) == code.to_s
      update!(otp_code_digest: nil, otp_expires_at: nil, otp_attempts: 0, otp_verified_at: Time.current)
      true
    else
      increment!(:otp_attempts)
      false
    end
  end

  def otp_pending?
    otp_code_digest.present? && !otp_expired?
  end

  def otp_expired?
    otp_expires_at.blank? || otp_expires_at.past?
  end

  def otp_locked?
    otp_attempts >= MAX_OTP_ATTEMPTS
  end
end
