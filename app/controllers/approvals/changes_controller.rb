# frozen_string_literal: true

# Approvals, in two columns. With no change open: the changes in the first
# (waiting, or decided) and a word on what to do in the second. With one
# open: what's live now in the first, what's proposed in the second, field by
# field, the proposal editable, to approve (Approvals::Changes::
# ApprovalsController) or reject (…::RejectionsController); Back, at the top
# right, brings the list back.
class Approvals::ChangesController < ApplicationController
  include PluginGated
  plugin :approvals

  LIST_SIZE = 100

  requires_capability "approvals:read", only: [:index, :show]

  def index
    @state = params[:state].presence_in(%w[pending decided]) || "pending"
    @counts = {"pending" => Approvals::Change.pending.count, "decided" => Approvals::Change.decided.count}
    @changes = Approvals::Change.public_send(@state).newest_first.limit(LIST_SIZE)
  end

  def show
    @change = Approvals::Change.find(params[:id])
  end
end
