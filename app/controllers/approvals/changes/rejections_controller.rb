# frozen_string_literal: true

# Rejecting a change: nothing it proposed is applied.
class Approvals::Changes::RejectionsController < ApplicationController
  include PluginGated
  plugin :approvals

  requires_capability "approvals:decide", only: :create

  def create
    change = Approvals::Change.find(params[:change_id])
    change.reject!(by: Current.user)
    redirect_to approvals_changes_path, notice: "Rejected — #{change.summary.sub(/\A\w+/) { it.downcase }} wasn't applied."
  rescue ArgumentError => e
    redirect_to approvals_change_path(change), alert: e.message
  end
end
