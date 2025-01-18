# frozen_string_literal: true

module GoodJob
  class PausesController < ApplicationController
    def index
      @paused = GoodJob::Setting.paused
    end

    def create
      return redirect_to({ action: :index }) unless params[:type].in?(%w[queue job_class]) && params[:value].present?

      GoodJob::Setting.pause(params[:type].to_sym => params[:value])
      redirect_to(good_job.pauses_path, notice: "Successfully paused #{params[:type]} '#{params[:value]}'")
    end

    def destroy
      return redirect_to({ action: :index }) unless params[:type].in?(%w[queue job_class]) && params[:value].present?

      GoodJob::Setting.unpause(params[:type].to_sym => params[:value].to_s)
      redirect_to(good_job.pauses_path, notice: "Successfully unpaused #{params[:type]} '#{params[:value]}'")
    end
  end
end
