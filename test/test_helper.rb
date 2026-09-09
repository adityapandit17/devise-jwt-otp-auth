ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Reads the code out of the most recently delivered email. Parts have to be
    # decoded: the multipart container body only holds boundaries, and
    # quoted-printable encoding can wrap a long line mid-number.
    def otp_code_from_last_email
      mail = ActionMailer::Base.deliveries.last
      return nil if mail.nil?

      parts = mail.multipart? ? mail.all_parts : [ mail ]
      parts.filter_map { |part| part.decoded[/\d{#{User::OTP_LENGTH}}/] }.first
    end
  end
end
