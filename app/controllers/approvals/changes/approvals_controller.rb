# frozen_string_literal: true

# Approving a change: the proposal, as the person edited it, goes live. It
# takes approvals:decide and the capability that puts the change live
# (pages:publish, entries:delete, …).
class Approvals::Changes::ApprovalsController < ApplicationController
  include PluginGated
  plugin :approvals

  requires_capability "approvals:decide", only: :create

  def create
    @change = Approvals::Change.find(params[:change_id])
    raise Authorization::Forbidden, @change.capability_to_decide unless Current.user.can?(@change.capability_to_decide)

    record = @change.approve!(params.fetch(:fields, {}).to_unsafe_h, by: Current.user)
    redirect_to approvals_changes_path, notice: "Approved — #{@change.summary.sub(/\A\w+/) { it.downcase }} is live#{" (in the trash)" if record.nil?}."
  rescue Approvals::Change::InvalidEdit, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
    @edits = params.fetch(:fields, {}).to_unsafe_h
    flash.now[:alert] = "Not approved: #{e.message}"
    render "approvals/changes/show", status: :unprocessable_content
  end
end
