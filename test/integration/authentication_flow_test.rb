require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  EMAIL = "api@example.com".freeze
  PASSWORD = "password".freeze

  setup do
    ActionMailer::Base.deliveries.clear
  end

  # ==> Registration

  test "signup creates the user and returns no token" do
    assert_emails 1 do
      post "/signup", params: { user: credentials }, as: :json
    end

    assert_response :created
    assert_equal true, response.parsed_body["otp_required"]
    assert_equal EMAIL, response.parsed_body["email"]
    assert User.exists?(email: EMAIL)
  end

  test "signup does not dispatch a token" do
    post "/signup", params: { user: credentials }, as: :json

    assert_response :created
    assert_nil response.headers["Authorization"],
               "a token before OTP verification would defeat the second factor"
  end

  test "signup rejects a mismatched password confirmation" do
    assert_no_emails do
      post "/signup", params: {
        user: { email: EMAIL, password: PASSWORD, password_confirmation: "different" }
      }, as: :json
    end

    assert_response :unprocessable_content
    assert_not_empty response.parsed_body["errors"]
    assert_not User.exists?(email: EMAIL)
  end

  test "signup rejects a duplicate email" do
    create_user

    post "/signup", params: { user: credentials }, as: :json

    assert_response :unprocessable_content
    assert_equal 1, User.where(email: EMAIL).count
  end

  test "signup rejects a short password" do
    post "/signup", params: {
      user: { email: EMAIL, password: "abc", password_confirmation: "abc" }
    }, as: :json

    assert_response :unprocessable_content
  end

  # ==> Login (first factor)

  test "login with a correct password emails a code and returns no token" do
    create_user

    assert_emails 1 do
      post "/login", params: { user: { email: EMAIL, password: PASSWORD } }, as: :json
    end

    assert_response :success
    assert_equal true, response.parsed_body["otp_required"]
    assert_nil response.headers["Authorization"],
               "the password alone must not earn a token"
  end

  test "login with a wrong password is rejected and sends nothing" do
    create_user

    assert_no_emails do
      post "/login", params: { user: { email: EMAIL, password: "wrong" } }, as: :json
    end

    assert_response :unauthorized
  end

  test "login with an unknown email is rejected" do
    post "/login", params: { user: { email: "nobody@example.com", password: PASSWORD } }, as: :json

    assert_response :unauthorized
  end

  # ==> OTP verification (second factor)

  test "verifying the emailed code returns a token" do
    create_user
    code = request_code

    post "/otp/verify", params: { email: EMAIL, code: code }, as: :json

    assert_response :success
    assert_equal EMAIL, response.parsed_body.dig("user", "email")
    assert_match(/\ABearer .+/, response.headers["Authorization"].to_s)
  end

  test "verifying a wrong code is rejected" do
    create_user
    request_code

    post "/otp/verify", params: { email: EMAIL, code: "000000" }, as: :json

    assert_response :unauthorized
    assert_nil response.headers["Authorization"]
  end

  test "a code cannot be replayed" do
    create_user
    code = request_code

    post "/otp/verify", params: { email: EMAIL, code: code }, as: :json
    assert_response :success

    post "/otp/verify", params: { email: EMAIL, code: code }, as: :json
    assert_response :unauthorized
  end

  test "an expired code is rejected" do
    user = create_user
    code = request_code
    user.update!(otp_expires_at: 1.second.ago)

    post "/otp/verify", params: { email: EMAIL, code: code }, as: :json

    assert_response :unauthorized
  end

  test "the correct code is refused once attempts are exhausted" do
    create_user
    code = request_code

    User::MAX_OTP_ATTEMPTS.times do
      post "/otp/verify", params: { email: EMAIL, code: "000000" }, as: :json
      assert_response :unauthorized
    end

    post "/otp/verify", params: { email: EMAIL, code: code }, as: :json

    assert_response :unauthorized
  end

  test "verifying against an unknown email is rejected" do
    post "/otp/verify", params: { email: "nobody@example.com", code: "000000" }, as: :json

    assert_response :unauthorized
  end

  # ==> Resending

  test "resend emails a fresh working code" do
    create_user
    first_code = request_code

    assert_emails 1 do
      post "/otp/resend", params: { email: EMAIL }, as: :json
    end
    assert_response :accepted

    second_code = otp_code_from_last_email
    assert_not_equal first_code, second_code

    post "/otp/verify", params: { email: EMAIL, code: second_code }, as: :json
    assert_response :success
  end

  test "resend clears a lockout" do
    create_user
    request_code
    User::MAX_OTP_ATTEMPTS.times do
      post "/otp/verify", params: { email: EMAIL, code: "000000" }, as: :json
    end

    post "/otp/resend", params: { email: EMAIL }, as: :json

    post "/otp/verify", params: { email: EMAIL, code: otp_code_from_last_email }, as: :json
    assert_response :success
  end

  test "resend for an unknown email looks identical but sends nothing" do
    create_user
    post "/otp/resend", params: { email: EMAIL }, as: :json
    known_status, known_body = response.status, response.parsed_body

    ActionMailer::Base.deliveries.clear

    assert_no_emails do
      post "/otp/resend", params: { email: "nobody@example.com" }, as: :json
    end

    assert_equal known_status, response.status, "the response must not reveal whether the account exists"
    assert_equal known_body, response.parsed_body
  end

  # ==> Using and revoking the token

  test "a protected route rejects a request with no token" do
    get "/me"

    assert_response :unauthorized
  end

  test "a protected route rejects a garbage token" do
    get "/me", headers: { "Authorization" => "Bearer not-a-real-token" }

    assert_response :unauthorized
  end

  test "an unauthorized error is JSON when the client asks for JSON" do
    get "/me", headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_not_empty response.parsed_body["error"]
  end

  test "a protected route accepts a verified token" do
    create_user

    get "/me", headers: { "Authorization" => token_for }

    assert_response :success
    assert_equal EMAIL, response.parsed_body.dig("user", "email")
  end

  test "logout revokes the token" do
    create_user
    token = token_for

    delete "/logout", headers: { "Authorization" => token }
    assert_response :no_content

    get "/me", headers: { "Authorization" => token }
    assert_response :unauthorized
  end

  test "logging out once does not revoke a token issued later" do
    create_user
    first_token = token_for
    delete "/logout", headers: { "Authorization" => first_token }

    second_token = token_for

    get "/me", headers: { "Authorization" => second_token }
    assert_response :success
  end

  test "the whole signup through authenticated request path works" do
    post "/signup", params: { user: credentials }, as: :json
    assert_response :created

    post "/otp/verify", params: { email: EMAIL, code: otp_code_from_last_email }, as: :json
    assert_response :success
    token = response.headers["Authorization"]

    get "/me", headers: { "Authorization" => token }
    assert_response :success

    delete "/logout", headers: { "Authorization" => token }
    assert_response :no_content

    get "/me", headers: { "Authorization" => token }
    assert_response :unauthorized
  end

  private

  def credentials
    { email: EMAIL, password: PASSWORD, password_confirmation: PASSWORD }
  end

  def create_user
    User.create!(credentials)
  end

  # Triggers a delivery and returns the code that was emailed.
  def request_code
    post "/login", params: { user: { email: EMAIL, password: PASSWORD } }, as: :json
    otp_code_from_last_email
  end

  # Completes both factors and returns the "Bearer ..." header value.
  def token_for
    post "/otp/verify", params: { email: EMAIL, code: request_code }, as: :json
    response.headers["Authorization"]
  end
end
