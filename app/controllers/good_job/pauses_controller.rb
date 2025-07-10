# frozen_string_literal: true

module GoodJob
  class PausesController < ApplicationController
    before_action :validate_type, only: [:create, :destroy]
    def index
      @paused = GoodJob::Setting.paused
    end

    def create
      pause_type = params[:type].to_sym
      pause_value = params[:value].to_s

      GoodJob::Setting.pause(pause_type => pause_value)
      redirect_to({ action: :index }, notice: "Successfully paused #{params[:type]} '#{params[:value]}'", status: :see_other)
    end

    def destroy
      pause_type = params[:type].to_sym
      pause_value = params[:value].to_s

      GoodJob::Setting.unpause(pause_type => pause_value)
      redirect_to({ action: :index }, notice: "Successfully unpaused #{params[:type]} '#{params[:value]}'", status: :see_other)
    end

    private

    def validate_type
      return if params[:type].in?(%w[queue job_class label]) && params[:value].to_s.present?

      raise ActionController::BadRequest, "Invalid type"
    end
  end
end
