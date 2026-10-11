# frozen_string_literal: true

# The <link> to the plugin's stylesheet (Approvals::StylesheetsController),
# for each Approvals screen's <head>.
module Approvals::StylesheetHelper
  def approvals_stylesheet_tag
    digest = (@approvals_css_digest ||= Digest::SHA1.file(Approvals::StylesheetsController::FILE).hexdigest[0, 10])
    tag.link(rel: "stylesheet", href: approvals_stylesheet_path(v: digest))
  end
end
