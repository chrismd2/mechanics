# Changelog

## 2026-08-06 — invites-owner-listing-invite-without-chat

- Let listing owners create shareable listing invites from Account and listing edit (no chat required)
- Show the share link on the current page after create instead of putting it in a flash notification
- Build invite share URLs from the request host (not Endpoint localhost) so links use the public domain
- Add `POST /listings/:listing_id/invites` wired to `Invites.create_listing_invite/2`

## 2026-08-06 — deploy-workflow-gha-tests

- Run `mix test` in GitHub Actions (Postgres service) before SSH deploy
- Stop running `make test mechanics` on the production host during deploy
