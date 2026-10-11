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

    # An object (SEO, fields, a global's data) is compared and edited key by
    # key, a key holding more than a plain value (SEO's JSON-LD) as JSON of
    # its own; anything else (blocks) as a whole.
    def by_key?
      sides = [live, proposed].compact
      json? && sides.any? && sides.all? { it.is_a?(Hash) }
    end

    # What differs inside a JSON value (the blocks, a key's JSON-LD), and
    # nothing else: [label, live, proposed] for each smallest part that
    # changed (Comparison.leaf_changes), labelled from here down.
    def changes(within: label, live: self.live, proposed: self.proposed)
      Approvals::Change.leaf_changes(live, proposed).map do |path, before, after|
        [[within, *path].join(" › "), before, after]
      end
    end

    # [key, label, live, proposed, changed?, nested?] for each key either side has.
    def keys
      live_hash = live.to_h.stringify_keys
      proposed_hash = proposed.to_h.stringify_keys
      (live_hash.keys | proposed_hash.keys).map do |key|
        nested = [live_hash[key], proposed_hash[key]].any? { it.is_a?(Hash) || it.is_a?(Array) }
        [key, "#{label} › #{Approvals::Change.key_label(key)}", live_hash[key], proposed_hash[key],
          Approvals::Change.normalize(live_hash[key]) != Approvals::Change.normalize(proposed_hash[key]), nested]
      end
    end
  end

  class_methods do
    def editable_fields(type) = FIELDS.fetch(type, [])

    def fields_of(record)
      editable_fields(record.class.name).to_h { |name, _| [name, record.public_send(name)] }
    end

    # A key as people read it: JSON-LD, not "Json ld".
    def key_label(key) = {"json_ld" => "JSON-LD", "og_image_id" => "Share image", "og_title" => "Share title",
      "og_description" => "Share description", "og_type" => "Open Graph type"}.fetch(key.to_s) { key.to_s.humanize }

    # [[path, live, proposed]] for each part of two JSON values that differs:
    # objects key by key, lists item by item — blocks matched by their id
    # where they all have one, so one moved or added doesn't make the rest
    # look changed (a move is an "Order" row of its own). A path reads as
    # people do: "3 · Hero", "Heading" (a block's "data" is left out).
    def leaf_changes(live, proposed, path = [])
      live = normalize(live)
      proposed = normalize(proposed)
      return [] if live == proposed

      if live.is_a?(Hash) && proposed.is_a?(Hash)
        (live.keys | proposed.keys).flat_map do |key|
          leaf_changes(live[key], proposed[key], key == "data" ? path : path + [key_label(key)])
        end
      elsif live.is_a?(Array) && proposed.is_a?(Array)
        list_changes(live, proposed, path)
      else
        [[path, live, proposed]]
      end
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

  class_methods do
    private

    def list_changes(live, proposed, path)
      ids = ->(list) { list.all? { it.is_a?(Hash) && it["id"].present? } ? list.map { it["id"] } : nil }
      live_ids, proposed_ids = ids.(live), ids.(proposed)
      return indexed_changes(live, proposed, path) unless live_ids && proposed_ids

      rows = proposed.each_with_index.flat_map do |item, index|
        before = live.find { it["id"] == item["id"] }
        leaf_changes(before, item, path + [item_label(item, index)])
      end
      rows += live.each_with_index.filter_map do |item, index|
        [path + [item_label(item, index)], item, nil] unless proposed_ids.include?(item["id"])
      end
      kept = live_ids & proposed_ids
      if (live_ids & kept) != (proposed_ids & kept)
        rows << [path + ["Order"], live.map.with_index { item_label(_1, _2) }.join("\n"), proposed.map.with_index { item_label(_1, _2) }.join("\n")]
      end
      rows
    end

    def indexed_changes(live, proposed, path)
      [live.size, proposed.size].max.times.flat_map do |index|
        item = proposed[index] || live[index]
        leaf_changes(live[index], proposed[index], path + [item_label(item, index)])
      end
    end

    # "3 · Hero" for a block, "3" for anything else in a list.
    def item_label(item, index)
      type = item["type"] if item.is_a?(Hash)
      type.present? ? "#{index + 1} · #{type.to_s.humanize}" : (index + 1).to_s
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
