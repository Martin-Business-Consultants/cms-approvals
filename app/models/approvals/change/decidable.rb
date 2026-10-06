# frozen_string_literal: true

# Deciding a change. Approving applies the proposal as the person edited it
# and puts it live (published, for a record with a status); a delete moves
# the record to the trash. Rejecting leaves everything as it is.
module Approvals::Change::Decidable
  extend ActiveSupport::Concern

  # A JSON field a person edited into something that doesn't parse.
  class InvalidEdit < StandardError; end

  # Applies `edits` ({field => value as typed}) over the proposal, and
  # returns the record now live (nil for a delete).
  def approve!(edits = {}, by:)
    raise ArgumentError, "already #{state}" unless pending?

    transaction do
      record = action == "destroy" ? trash_subject : apply(attributes_with(edits))
      update!(state: "approved", decided_by: by, decided_at: Time.current, subject_id: record&.id || subject_id,
        payload: action == "destroy" ? payload : attributes_with(edits))
      Event.record("approval.approved", target: record, change_id: id, summary: summary)
      record
    end
  end

  def reject!(by:)
    raise ArgumentError, "already #{state}" unless pending?

    update!(state: "rejected", decided_by: by, decided_at: Time.current)
    Event.record("approval.rejected", target: subject, change_id: id, summary: summary)
  end

  # The capability approving takes: the one that puts the change live.
  def capability_to_decide = action == "destroy" ? "#{prefix}:delete" : "#{prefix}:publish"

  private

  def attributes_with(edits)
    typed = self.class.editable_fields(subject_type).to_h
    edited = edits.to_h.stringify_keys.slice(*typed.keys).to_h do |name, value|
      [name, typed[name] == "json" ? parse_json(name, value) : value.to_s.gsub("\r\n", "\n")]
    end
    payload.merge(edited)
  end

  def parse_json(name, value)
    return value unless value.is_a?(String)

    value.strip.empty? ? nil : JSON.parse(value)
  rescue JSON::ParserError => e
    raise InvalidEdit, "#{name == "seo" ? "SEO" : name.humanize} isn't valid JSON: #{e.message.lines.first.strip}"
  end

  def apply(attributes)
    record = action == "create" ? build_subject : subject
    raise ActiveRecord::RecordNotFound, "the #{kind} is gone" if record.nil?

    prior = record.try(:status)
    record.assign_attributes(attributes)
    record.status = "published" if record.respond_to?(:status)
    record.save!
    track(record, prior)
    record
  end

  def build_subject
    case subject_type
    when "CollectionEntry" then Collection.find(collection_id).entries.new
    else subject_type.constantize.new
    end
  end

  def track(record, prior)
    if action == "create" then record.track_creation
    elsif record.is_a?(Global) then record.track_update
    else record.track_update(from: prior)
    end
  end

  def trash_subject
    record = subject or raise ActiveRecord::RecordNotFound, "the #{kind} is gone"
    record.trash
    nil
  end
end
