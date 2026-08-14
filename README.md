# Mechanics

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## CI / Deploy

The [deploy workflow](.github/workflows/deploy.yml) runs `mix test` (with Postgres) before deploying on push to `main`/`master`, non-draft PR open / synchronize / ready for review, or manual dispatch. On the server it checks out the triggering remote branch, then `make down/build/up mechanics`.

## Vehicle pricing

Users with the `pricing_user` role can submit observed vehicle market prices (listing or sale) and request competitive and expected-minimum suggestions via a pricing agent that queries that stored data. See [docs/pricing.md](docs/pricing.md).

Multi-source auction comps (BidWrangler + Royal Auction) are queried by the pricing agent tools during suggestions. Admins manage origins in [docs/listing-search.md](docs/listing-search.md).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
