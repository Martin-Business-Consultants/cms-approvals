# frozen_string_literal: true

# GET /api/approvals — the changes waiting for a person (?state=approved,
# rejected or all for others), and GET /api/approvals/:id — one, and what
# became of it: how an agent follows up a write the API held (202).
class Approvals::Api::ChangesController < Api::BaseController
  include PluginGated
  plugin :approvals

  enforce_authorization
  requires_capability "approvals:read", only: [:index, :show]

  def index
    state = params[:state].presence_in(%w[pending approved rejected all]) || "pending"
    scope = state == "all" ? Approvals::Change.all : Approvals::Change.where(state: state)
    @changes = scope.newest_first.limit(100)
  end

  def show
    @change = Approvals::Change.find(params[:id])
  end
end
