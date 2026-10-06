# frozen_string_literal: true

# A content change made through the API with a token — an agent's work through
# the `cms` CLI or MCP — held for a person instead of applied (Holdable). It
# keeps what the write would set (`payload`) and, for a change to something
# that exists, the fields as they were (`base`). A person compares it with
# what's live (Comparison), edits the proposal, and approves it — which puts
# it live — or rejects it (Decidable).
class Approvals::Change < ApplicationRecord
  include Holdable
  include Comparison
  include Decidable

  ACTIONS = %w[create update destroy].freeze
  STATES = %w[pending approved rejected].freeze

  belongs_to :proposer, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  validates :action, inclusion: {in: ACTIONS}
  validates :state, inclusion: {in: STATES}

  scope :pending, -> { where(state: "pending") }
  scope :decided, -> { where.not(state: "pending") }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def pending? = state == "pending"

  # The record it changes, trashed or not; nil for a create not yet approved.
  def subject
    return if subject_id.nil?

    model = subject_type.constantize
    (model.respond_to?(:with_discarded) ? model.with_discarded : model).find_by(id: subject_id)
  end

  def collection = collection_id && Collection.find_by(id: collection_id)

  def kind = {"Page" => "page", "CollectionEntry" => "entry", "Global" => "global"}.fetch(subject_type, subject_type.underscore)

  # "Update page “About”", "Create entry in Posts", "Delete global “Footer”".
  def summary
    verb = {"create" => "Create", "update" => "Update", "destroy" => "Delete"}.fetch(action)
    name = payload["title"].presence || payload["name"].presence || base["title"].presence || base["name"].presence ||
      payload["slug"].presence || base["slug"]
    where = " in #{collection.name}" if kind == "entry" && collection
    [verb, kind, (name && "“#{name}”"), where].compact.join(" ")
  end
end
