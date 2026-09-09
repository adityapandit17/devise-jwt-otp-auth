require "test_helper"

class OtpMailerTest < ActionMailer::TestCase
  setup do
    @user = User.create!(email: "mailer@example.com", password: "password")
  end

  test "addresses the email to the user" do
    mail = OtpMailer.code(@user, "123456")

    assert_equal [ @user.email ], mail.to
    assert_equal "Your verification code", mail.subject
  end

  test "includes the code in both the html and text parts" do
    mail = OtpMailer.code(@user, "123456")

    assert_includes mail.html_part.decoded, "123456"
    assert_includes mail.text_part.decoded, "123456"
  end

  test "tells the recipient how long the code lasts" do
    mail = OtpMailer.code(@user, "123456")
    expected = (User::OTP_VALIDITY / 60).to_i.to_s

    assert_includes mail.text_part.decoded, expected
  end
end
