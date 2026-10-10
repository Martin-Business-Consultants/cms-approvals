# frozen_string_literal: true

# What's live beside what's proposed, field by field: the fields a person can
# edit for each kind of record, their values on each side, and which differ.
module Approvals::Change::Comparison
  extend ActiveSupport::Concern

  # [name, kind] per record type; kind is how the field is shown and edited.
  FIELDS = {
    "Page" => [%w[title text], %w[slug text], %w[blocks json], %w[frontmatter json], %w[seo json]],
    "CollectionEntry" => [%w[title text], %w[slug text], %w[body_markdown markdown], %w[blocks json],
      %w[frontmatter json], %w[seo json]],
    "Global" => [%w[name text], %w[slug text], %w[description text], %w[data json]]
  }.freeze

  Field = Data.define(:name, :kind, :live, :proposed) do
    def label = {"body_markdown" => "Body", "seo" => "SEO"}.fetch(name) { name.humanize }
    def changed? = Approvals::Change.normalize(live) != Approvals::Change.normalize(proposed)
    def json? = kind == "json"

    # An object of plain values (SEO, fields, a global's data) is compared
    # and edited key by key; anything else (blocks) as a whole.
    def by_key?
      json? && [live, proposed].compact.all? { it.is_a?(Hash) } && [live, proposed].compact.any? &&
        [live, proposed].compact.flat_map(&:values).none? { it.is_a?(Hash) || it.is_a?(Array) }
    end

    # [key, label, live, proposed, changed?] for each key either side has.
    def keys
      live_hash = live.to_h.stringify_keys
      proposed_hash = proposed.to_h.stringify_keys
      (live_hash.keys | proposed_hash.keys).map do |key|
        [key, "#{label} › #{key.humanize}", live_hash[key], proposed_hash[key],
          Approvals::Change.normalize(live_hash[key]) != Approvals::Change.normalize(proposed_hash[key])]
      end
    end
  end

  class_methods do
    def editable_fields(type) = FIELDS.fetch(type, [])

    def fields_of(record)
      editable_fields(record.class.name).to_h { |name, _| [name, record.public_send(name)] }
    end

    def normalize(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, normalize(v)] }
      when Array then value.map { normalize(it) }
      when nil then nil
      else value.to_s
      end
    end
  end

  # Each editable field, live (now, or as it was when proposed once the record
  # is gone) and proposed (the payload over the live value).
  def fields
    now = live_fields
    self.class.editable_fields(subject_type).map do |name, kind|
      proposed = action == "destroy" ? nil : payload.fetch(name) { now[name] }
      Field.new(name: name, kind: kind, live: now[name], proposed: proposed)
    end
  end

  def changed_fields = fields.select(&:changed?)

  # What the write sets beyond the editable fields (status, parent, tags…),
  # applied as proposed.
  def other_attributes
    payload.except(*self.class.editable_fields(subject_type).map(&:first))
  end

  # The live record has changed since this was proposed.
  def stale?
    record = subject
    action != "create" && record && base_updated_at && record.updated_at.to_i != base_updated_at.to_i
  end

  private

  def live_fields
    record = subject
    record && action != "create" ? self.class.fields_of(record) : base
  end
end
