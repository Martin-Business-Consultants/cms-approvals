# Approvals

A plugin for the CMS (see `docs/plugins.md` in [LibrePublish CMS](https://github.com/Martin-Business-Consultants/cmsv2)).

Content changes made through the API with a token — an agent's work through the
`cms` CLI or MCP — wait in **Approvals** instead of going live. The API answers
`202` with `"status": "pending_approval"` and the approval's id. A person opens
the change and sees what's live in the first column and the proposal in the
second, field by field, with what differs marked; edits the proposal as needed;
and approves it, which puts it live (published, for a page or an entry; a
delete goes to the trash), or rejects it.

Held: creating, changing and deleting pages, collection entries and globals.
While it's on, the bulk content endpoints refuse tokens (`409`), so nothing
goes round it. A person signed in to the admin works as usual. Structure
(collections, schemas, block types), media and settings aren't held.

Approving takes `approvals:decide` and the capability that puts the change
live (`pages:publish`, `entries:publish`, `globals:publish`, or `:delete` for
a delete). Agents can follow a change at `GET /api/approvals/:id`.

Install it into a CMS checkout:

    bin/rails "plugins:install[<this repository's git URL>]"

or, on a Docker install, add the URL to the `CMS_PLUGINS` builder secret. Then
switch it on in Settings › Plugins.

Its specs run inside the CMS, with the plugin installed in `plugins/approvals`:

    bin/rspec plugins/approvals/spec
