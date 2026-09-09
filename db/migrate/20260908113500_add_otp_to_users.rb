class AddOtpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_code_digest, :string
    add_column :users, :otp_expires_at, :datetime
    add_column :users, :otp_attempts, :integer, default: 0, null: false
    add_column :users, :otp_verified_at, :datetime
  end
end
