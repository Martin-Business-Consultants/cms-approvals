# frozen_string_literal: true

require "rails_helper"

# The Approvals plugin: content changes made through the API with a token are
# held (202) instead of applied, listed for a person, compared with what's
# live, edited and approved — which puts them live — or rejected.
RSpec.describe "The Approvals plugin", type: :request do
  let(:admin) { create(:user) }
  let(:agent) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write entries:read entries:write globals:read globals:write globals:delete approvals:read])) }
  let(:token) { {"Authorization" => "Bearer #{agent.api_token.token}"} }

  def live_page(**attrs)
    Page.create!({slug: "about", title: "About", status: "published", locale: "en",
                  blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "Old"}}]}.merge(attrs))
  end

  def json = JSON.parse(response.body)

  before do
    switch_plugin :approvals, on: true
    BlockType.create!(slug: "text", label: "Text", fields: [{"name" => "body", "type" => "text", "label" => "Body"}])
  end

  describe "holding API writes" do
    it "holds a token's change to a page instead of applying it, and says where to follow it up" do
      page = live_page

      patch "/api/pages/about", params: {page: {title: "About us"}}, headers: token, as: :json

      expect(response).to have_http_status(:accepted)
      expect(json["status"]).to eq("pending_approval")
      expect(json.dig("approval", "summary")).to eq("Update page “About us”")
      expect(page.reload.title).to eq("About")

      get json.dig("approval", "api_path"), headers: token
      expect(json.dig("approval", "state")).to eq("pending")
      expect(json.dig("approval", "changed")).to eq(["title"])
    end

    it "holds creates and deletes too, for pages, entries and globals" do
      live_page
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      post "/api/pages", params: {page: {slug: "new", title: "New", status: "draft", locale: "en"}}, headers: token, as: :json
      post "/api/collections/posts/entries", params: {entry: {slug: "hi", title: "Hi"}}, headers: token, as: :json
      delete "/api/globals/footer", headers: token

      expect(response).to have_http_status(:accepted)
      expect(Approvals::Change.pending.pluck(:action, :subject_type))
        .to contain_exactly(%w[create Page], %w[create CollectionEntry], %w[destroy Global])
      expect(Page.exists?(slug: "new")).to be(false)
      expect(collection.entries.count).to eq(0)
      expect(Global.exists?(slug: "footer")).to be(true)
    end

    it "lets a person's own writes, and every write while it's off, through" do
      live_page
      patch "/api/pages/about", params: {page: {title: "Mine"}}, headers: {"Authorization" => "Bearer #{admin.api_token.token}"}, as: :json
      expect(response).to have_http_status(:accepted)

      switch_plugin :approvals, on: false
      patch "/api/pages/about", params: {page: {title: "Mine"}}, headers: {"Authorization" => "Bearer #{admin.api_token.token}"}, as: :json
      expect(response).to have_http_status(:ok)
      expect(Page.find_by(slug: "about").title).to eq("Mine")
    end

    it "refuses the bulk endpoints to a token, so nothing goes round it" do
      live_page
      post "/api/pages/bulk_update_status", params: {slugs: ["about"], status: "draft"},
        headers: {"Authorization" => "Bearer #{admin.api_token.token}"}, as: :json

      expect(response).to have_http_status(:conflict)
      expect(Page.find_by(slug: "about").status).to eq("published")
    end
  end

  describe "deciding" do
    it "shows what's live beside the proposal, and puts the edited proposal live" do
      page = live_page(status: "draft")
      patch "/api/pages/about", params: {page: {title: "About us", blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "New"}}]}},
        headers: token, as: :json
      change = Approvals::Change.last
      sign_in_as admin

      get approvals_changes_path
      expect(response.body).to include("Update page “About us”", agent.name.to_s)

      get approvals_change_path(change)
      expect(response.body).to include("Live now", "Proposed", "Approve and put live", "Back to the list", %(href="#{approvals_changes_path}"))
      expect(response.body).to include("About", "About us", "approvals__cell--added")

      post approvals_change_approval_path(change), params: {fields: {title: "About our team", blocks: change.payload["blocks"].to_json}}

      expect(response).to redirect_to(approvals_changes_path)
      expect(page.reload).to have_attributes(title: "About our team", status: "published")
      expect(page.blocks.first.dig("data", "body")).to eq("New")
      expect(change.reload).to have_attributes(state: "approved", decided_by: admin)
      expect(AuditLog.where(action: "approval.approved")).to exist
    end

    it "lists the changes beside a word on what to do, and compares an SEO change key by key" do
      page = live_page
      page.update!(seo: {"meta_title" => "About", "meta_description" => "Old words"})
      patch "/api/pages/about", params: {page: {seo: {"meta_title" => "About", "meta_description" => "A clearer description of the team."}}},
        headers: token, as: :json
      change = Approvals::Change.last
      sign_in_as admin

      get approvals_changes_path
      expect(response.body).to include("Waiting", "Open a change to compare it", approvals_change_path(change))

      get approvals_change_path(change)
      expect(response.body).to include("SEO › Meta description", "Old words", "A clearer description of the team.")
      expect(response.body).not_to include("SEO › Meta title")

      post approvals_change_approval_path(change), params: {fields: {seo: {meta_description: "Edited by a person."}}}
      expect(page.reload.seo).to include("meta_title" => "About", "meta_description" => "Edited by a person.")
    end

    it "shows a proposal's JSON-LD as its own block beside the SEO keys, and takes it as edited" do
      page = live_page
      page.update!(seo: {"meta_title" => "About", "meta_description" => "Who we are."})
      json_ld = {"@context" => "https://schema.org", "@type" => "AboutPage", "name" => "About"}
      patch "/api/pages/about", params: {page: {seo: {"meta_title" => "About", "meta_description" => "Who we are.", "json_ld" => json_ld}}},
        headers: token, as: :json
      change = Approvals::Change.last
      sign_in_as admin

      get approvals_change_path(change)
      expect(response.body).to include("SEO › JSON-LD", "&quot;@type&quot;: &quot;AboutPage&quot;")
      expect(response.body).not_to include("SEO › Meta description")

      post approvals_change_approval_path(change), params: {fields: {seo: {json_ld: "{nope"}}}
      expect(response.body).to include("SEO › JSON-LD isn&#39;t valid JSON")

      edited = json_ld.merge("name" => "About the team").to_json
      post approvals_change_approval_path(change), params: {fields: {seo: {json_ld: edited}}}
      expect(page.reload.seo).to include("meta_description" => "Who we are.", "json_ld" => json_ld.merge("name" => "About the team"))
    end

    it "creates and deletes on approval" do
      Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})
      post "/api/collections/posts/entries", params: {entry: {slug: "hi", title: "Hi", body_markdown: "Hello"}}, headers: token, as: :json
      delete "/api/globals/footer", headers: token
      sign_in_as admin

      Approvals::Change.pending.order(:id).each { post approvals_change_approval_path(it) }

      expect(CollectionEntry.find_by(slug: "hi")).to have_attributes(status: "published", body_markdown: "Hello")
      expect(Global.exists?(slug: "footer")).to be(false)
    end

    # The review form posts every field it shows; one the proposal left out
    # (a new page's frontmatter) comes back empty and must not be applied as
    # a blank ("Frontmatter must be an object").
    it "approves a new page that left its frontmatter out, through the form as shown" do
      post "/api/pages", params: {page: {slug: "commercial", title: "Commercial", status: "draft", locale: "en",
        blocks: [{"type" => "text", "data" => {"body" => "Hi"}}]}}, headers: token, as: :json
      change = Approvals::Change.last
      sign_in_as admin

      shown = change.fields.to_h { |field| [field.name, field.json? ? field.proposed.to_json.then { it == "null" ? "" : it } : field.proposed.to_s] }
      post approvals_change_approval_path(change), params: {fields: shown}

      expect(Page.find_by(slug: "commercial")).to have_attributes(frontmatter: {}, status: "published", title: "Commercial")
      expect(change.reload.state).to eq("approved")
    end

    it "keeps the edits and says why when an edited JSON field doesn't parse" do
      live_page
      patch "/api/pages/about", params: {page: {title: "About us"}}, headers: token, as: :json
      sign_in_as admin

      post approvals_change_approval_path(Approvals::Change.last), params: {fields: {title: "Kept", seo: "{nope"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("SEO isn&#39;t valid JSON", "Kept")
      expect(Approvals::Change.last).to be_pending
    end

    it "rejects without applying anything" do
      page = live_page
      patch "/api/pages/about", params: {page: {title: "Nope"}}, headers: token, as: :json
      sign_in_as admin

      post approvals_change_rejection_path(Approvals::Change.last)

      expect(Approvals::Change.last).to have_attributes(state: "rejected")
      expect(page.reload.title).to eq("About")
    end

    it "takes the capability that puts the change live" do
      live_page
      patch "/api/pages/about", params: {page: {title: "About us"}}, headers: token, as: :json
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write approvals:read approvals:decide]))

      get approvals_change_path(Approvals::Change.last)
      expect(response.body).not_to include("Approve and put live")
      expect(response.body).to include("<code>pages:publish</code>")

      post approvals_change_approval_path(Approvals::Change.last)
      expect(Page.find_by(slug: "about").title).to eq("About")
    end

    it "is gone while switched off" do
      switch_plugin :approvals, on: false
      sign_in_as admin

      get approvals_changes_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
