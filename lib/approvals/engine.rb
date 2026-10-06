# frozen_string_literal: true

module Approvals
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    initializer "approvals.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "approvals.routes" do |app|
      app.routes.append do
        scope module: "approvals", as: "approvals" do
          resources :changes, path: "approvals", only: [:index, :show] do
            scope module: :changes do
              resource :approval, only: :create
              resource :rejection, only: :create
            end
          end
        end

        scope "api", module: "approvals/api", as: "api_approvals", defaults: {format: :json} do
          resources :changes, path: "approvals", only: [:index, :show]
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :approvals, name: "Approvals", version: "1.0.0", author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.0",
        description: "Content changes made through the API, the cms CLI or MCP — an agent's work — wait in a " \
                     "list for a person to edit and approve, which puts them live."

      Cms::Plugins.hold_api_writes :approvals, ->(write) { Approvals::Change.hold(write) }

      Cms::Plugins.menu :approvals, :approvals, label: "Approvals", icon: "check-circle", group: "Content", after: :start,
        path: -> { approvals_changes_path }, capability: "approvals:read"
      Cms::Plugins.permissions :approvals, "Approvals", %w[approvals:read approvals:decide],
        after: "Globals", defaults: {editor: %w[approvals:read approvals:decide], author: %w[approvals:read],
                                     agent: %w[approvals:read]}
      Cms::Plugins.stylesheet :approvals, "approvals/approvals"
      Cms::Plugins.counts :approvals, pending_approvals: -> { Approvals::Change.pending.count }

      Cms::Plugins.api :approvals, "/api/approvals",
        description: "Changes waiting for a person, and what became of them. A write the API held answers 202 with its id."
    end
  end
end
