# frozen_string_literal: true

# Holding a write: what Cms::Plugins.hold_api_writes calls with a
# Cms::Plugins::HeldWrite, and what the API answers (202) in its place.
module Approvals::Change::Holdable
  extend ActiveSupport::Concern

  class_methods do
    # The change held, as the API's answer; nil for an update that changes
    # nothing, which the API applies as the no-op it is.
    def hold(write)
      record = write.record
      return if write.action == "update" && !record.changed?

      live = record.persisted? ? record.class.find(record.id) : nil
      change = create!(action: write.action, prefix: write.prefix, subject_type: record.class.name,
        subject_id: live&.id, collection_id: record.try(:collection_id), payload: write.attributes,
        base: live ? fields_of(live) : {}, base_updated_at: live&.updated_at,
        proposed_by: proposer_name, proposer: Current.user)
      Event.record("approval.requested", target: live, change_id: change.id, summary: change.summary)
      change.held_response
    end

    private

    def proposer_name
      Current.user&.name.presence || Current.user&.email || Current.api_token.try(:name) || "API"
    end
  end

  # What the API answers in place of the record: it's waiting, and where.
  def held_response
    {status: "pending_approval", message: "Held for approval: a person reviews it before it goes live.",
     approval: {id: id, action: action, summary: summary, state: state, path: "/approvals/#{id}",
                api_path: "/api/approvals/#{id}"}}
  end
end
