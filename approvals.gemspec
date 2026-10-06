# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "approvals"
  spec.version = "1.0.0"
  spec.summary = "Holds content changes made through the API, CLI or MCP for a person to edit and approve"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
