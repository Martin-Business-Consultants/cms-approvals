# frozen_string_literal: true

# The list's bulk actions: the ticked changes approved as proposed, or
# rejected, one at a time. One that can't be (the role can't put it live,
# the record wouldn't take it, it's been decided meanwhile) is left waiting
# and named, and the rest go through.
class Approvals::BulkDecisionsController < ApplicationController
  include PluginGated
  plugin :approvals

  requires_capability "approvals:decide", only: :create

  def create
    approve = params[:decision] == "approve"
    changes = Approvals::Change.pending.where(id: Array(params[:ids])).order(:created_at).to_a
    return redirect_to(approvals_changes_path, alert: "Tick the changes to #{approve ? "approve" : "reject"} first.") if changes.empty?

    done, refused = [], []
    changes.each do |change|
      unless Current.user.can?(change.capability_to_decide)
        refused << "#{change.summary} (your role can't: #{change.capability_to_decide})"
        next
      end
      approve ? change.approve!({}, by: Current.user) : change.reject!(by: Current.user)
      done << change
    rescue Approvals::Change::InvalidEdit, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
      refused << "#{change.summary} (#{e.message})"
    end

    flash[:notice] = "#{approve ? "Approved" : "Rejected"} #{helpers.pluralize(done.size, "change")}." if done.any?
    flash[:alert] = "Left waiting: #{refused.join("; ")}." if refused.any?
    redirect_to approvals_changes_path
  end
end
