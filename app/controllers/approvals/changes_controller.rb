# frozen_string_literal: true

# Approvals: the changes waiting for a person, newest first, and the ones
# already decided; and one change, what's live beside what's proposed, to edit
# and approve (Approvals::Changes::ApprovalsController) or reject
# (Approvals::Changes::RejectionsController).
class Approvals::ChangesController < ApplicationController
  include PluginGated
  plugin :approvals

  requires_capability "approvals:read", only: [:index, :show]

  def index
    @state = params[:state].presence_in(%w[pending decided]) || "pending"
    @counts = {"pending" => Approvals::Change.pending.count, "decided" => Approvals::Change.decided.count}
    @changes = paginate(Approvals::Change.public_send(@state).newest_first)
  end

  def show
    @change = Approvals::Change.find(params[:id])
  end
end
