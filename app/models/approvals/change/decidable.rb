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
    proposed = fields.to_h { [it.name, it.proposed] }
    edited = edits.to_h.stringify_keys.slice(*typed.keys).to_h do |name, value|
      if typed[name] == "json" && value.is_a?(Hash)
        # Some of an object's keys, edited one by one (an SEO description),
        # over the rest of what was proposed.
        base = proposed[name].to_h.stringify_keys
        [name, base.merge(value.to_h.stringify_keys.to_h { |key, typed| [key, edited_key(name, key, base[key], typed)] })]
      else
        [name, typed[name] == "json" ? parse_json(name, value) : value.to_s.gsub("\r\n", "\n")]
      end
    end
    # A field the proposal left out comes back from the form as it was shown
    # (empty, for a new record's frontmatter): only a change to it counts, or
    # the record would be given a blank it can't take.
    edited.reject! { |name, value| !payload.key?(name) && Approvals::Change.normalize(value) == Approvals::Change.normalize(proposed[name]) }
    payload.merge(edited)
  end

  # One key of an object, as typed: JSON again for one that held more than a
  # plain value (JSON-LD), a whole number or yes/no again for a field that
  # holds one (the form posts every key as text), and nothing for one emptied.
  def edited_key(name, key, before, typed)
    text = typed.to_s.gsub("\r\n", "\n")
    return scalar_key(name, key, key_type(name, key, before), text) unless before.is_a?(Hash) || before.is_a?(Array) || text.lstrip.start_with?("{", "[")
    return nil if text.strip.empty?

    JSON.parse(text)
  rescue JSON::ParserError => e
    raise InvalidEdit, "#{key_path(name, key)} isn't valid JSON: #{e.message.lines.first.strip}"
  end

  def scalar_key(name, key, type, text)
    case type
    when "integer"
      text.strip.empty? ? nil : Integer(text.strip, 10)
    when "boolean"
      text.strip.empty? ? nil : ActiveModel::Type::Boolean.new.cast(text.strip)
    else
      text
    end
  rescue ArgumentError
    raise InvalidEdit, "#{key_path(name, key)} must be a whole number"
  end

  # The type a key holds: its field's, where the record has a schema for it
  # (frontmatter, a global's data), or else what it held before.
  def key_type(name, key, before)
    field = schema_fields(name).find { it.is_a?(Hash) && it["name"].to_s == key.to_s }
    return field["type"] if field

    case before
    when Integer then "integer"
    when true, false then "boolean"
    end
  end

  def schema_fields(name)
    fields =
      case [subject_type, name]
      when %w[CollectionEntry frontmatter] then collection&.fields
      when %w[Page frontmatter], %w[Global data] then subject&.fields
      end
    Array(fields)
  end

  def key_path(name, key) = "#{(name == "seo") ? "SEO" : name.humanize} › #{self.class.key_label(key)}"

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
