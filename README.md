# Mechanics

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## CI / Deploy

The [deploy workflow](.github/workflows/deploy.yml) runs `mix test` (with Postgres 16) in GitHub Actions before deploying on push to `main`/`master`, PR open, or manual dispatch. On the server it only pulls/merges and runs `make down/build/up mechanics` via `christenson_server_host`.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
