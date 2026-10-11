# frozen_string_literal: true

# The Approvals screens' stylesheet (lib/approvals/approvals.css), served by
# the plugin rather than the asset pipeline: a plugin added from Settings ›
# Plugins depends on the install compiling its assets when it boots, and one
# that doesn't (as one install didn't, 2026-10-11) leaves the screens
# unstyled. Its address carries its digest (Approvals::StylesheetHelper), so
# it's cached for good.
class Approvals::StylesheetsController < ActionController::Base
  FILE = Approvals::Engine.root.join("lib/approvals/approvals.css")

  def show
    expires_in 1.year, public: true
    send_file FILE, type: "text/css", disposition: :inline
  end
end
