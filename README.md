# Mechanics

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## CI / Deploy

The [deploy workflow](.github/workflows/deploy.yml) runs `mix test` (with Postgres 16) in GitHub Actions before deploying on push to `main`/`master`, PR open, or manual dispatch. On the server it only pulls/merges and runs `make down/build/up mechanics` via `christenson_server_host`.

## Invites

Shareable invite links deep-link into a conversation, listing discussion, or mechanic profile discussion after sign-in. Invites expire after 14 days and can be accepted once.

| Subject | Who can create | How |
| --- | --- | --- |
| Conversation | Chat participant with access | Chat page → Create invite link. The share URL and QR appear on that page. |
| Listing | Listing owner (or any signed-in user if the listing is public) | Account → Your listings, or listing edit page → Invite / Create invite link. The share URL and QR appear on that page (not in the flash). |
| Profile | Anyone (target must be a mechanic) | Context API (`Invites.create_profile_invite/2`) |

Listing owners can create a listing invite **without an existing chat**. A mechanic who accepts opens (or creates) a listing discussion with the owner.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
