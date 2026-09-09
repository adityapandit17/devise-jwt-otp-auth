# frozen_string_literal: true

class MeController < ApplicationController
  before_action :authenticate_user!

  # GET /me
  def show
    render json: { user: current_user.slice(:id, :email, :otp_verified_at) }
  end
end
