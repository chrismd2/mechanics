# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mechanics,
  ecto_repos: [Mechanics.Repo],
  generators: [binary_id: true, timestamp_type: :utc_datetime]

# Configures the endpoint
config :mechanics, MechanicsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MechanicsWeb.ErrorHTML, json: MechanicsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mechanics.PubSub,
  live_view: [signing_salt: "xGLjDTR+"]

# Configures the mailer (Swoosh). Default dev: Local + "/dev/mailbox". Test: Test adapter.
# config/runtime.exs switches to ZeptoMail (and optional SMTP) when MIX_ENV=prod or ENV=prod,
# or in dev when ZEPTO_SEND_MAIL_TOKEN or SMTP_HOST is set (e.g. Zepto sandbox key in .env).
config :mechanics, Mechanics.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  mechanics: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  mechanics: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
