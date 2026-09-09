require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = User.create!(
      email: "model@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  test "assigns a jti on create so tokens can be revoked" do
    assert_not_nil @user.jti
  end

  test "rotating the jti is what revokes a token" do
    payload = { "jti" => @user.jti }
    assert_not User.jwt_revoked?(payload, @user)

    User.revoke_jwt(payload, @user)

    assert User.jwt_revoked?(payload, @user.reload)
  end

  test "generate_otp! returns a code of the configured length" do
    code = @user.generate_otp!

    assert_match(/\A\d{#{User::OTP_LENGTH}}\z/, code)
  end

  test "generate_otp! stores only a digest, never the plaintext code" do
    code = @user.generate_otp!

    assert_not_equal code, @user.otp_code_digest
    assert_not_includes @user.otp_code_digest, code
  end

  test "generate_otp! sets an expiry and clears prior attempts" do
    @user.update!(otp_attempts: 3)

    @user.generate_otp!

    assert @user.otp_expires_at.future?
    assert_equal 0, @user.otp_attempts
  end

  test "generate_otp! issues a different code each time" do
    assert_not_equal @user.generate_otp!, @user.generate_otp!
  end

  test "verify_otp accepts the correct code" do
    code = @user.generate_otp!

    assert @user.verify_otp(code)
  end

  test "verify_otp consumes the code so it cannot be replayed" do
    code = @user.generate_otp!

    assert @user.verify_otp(code)
    assert_not @user.verify_otp(code)
    assert_nil @user.otp_code_digest
  end

  test "verify_otp records when the code was accepted" do
    code = @user.generate_otp!

    assert_nil @user.otp_verified_at
    @user.verify_otp(code)

    assert_not_nil @user.otp_verified_at
  end

  test "verify_otp rejects a wrong code and counts the attempt" do
    @user.generate_otp!

    assert_not @user.verify_otp("000000")
    assert_equal 1, @user.otp_attempts
  end

  test "verify_otp rejects a nil or blank code" do
    @user.generate_otp!

    assert_not @user.verify_otp(nil)
    assert_not @user.verify_otp("")
  end

  test "verify_otp rejects an expired code" do
    code = @user.generate_otp!
    @user.update!(otp_expires_at: 1.second.ago)

    assert_not @user.verify_otp(code)
  end

  test "verify_otp rejects the correct code once attempts are exhausted" do
    code = @user.generate_otp!

    User::MAX_OTP_ATTEMPTS.times { @user.verify_otp("000000") }

    assert @user.otp_locked?
    assert_not @user.verify_otp(code), "a locked account must not accept even the right code"
  end

  test "verify_otp fails when no code has been issued" do
    assert_nil @user.otp_code_digest
    assert_not @user.verify_otp("000000")
  end

  test "otp_pending? is only true while an unexpired code exists" do
    assert_not @user.otp_pending?

    @user.generate_otp!
    assert @user.otp_pending?

    @user.update!(otp_expires_at: 1.second.ago)
    assert_not @user.otp_pending?
  end

  test "deliver_otp! emails a code that verifies" do
    assert_emails 1 do
      @user.deliver_otp!
    end

    code = otp_code_from_last_email

    assert_not_nil code, "the email should contain the code"
    assert @user.reload.verify_otp(code)
  end
end
