# frozen_string_literal: true

require "approvals/engine"

# Approvals: content changes made through the API with a token — what an
# agent does through the `cms` CLI or MCP — wait in a list instead of going
# live. A person opens one, sees what's live beside the proposed version,
# edits the proposal as needed, and approves it, which puts it live; or
# rejects it. Installed from its own repository; off by default.
module Approvals
  # Plugin tables are prefixed with the plugin's key.
  def self.table_name_prefix = "approvals_"
end
