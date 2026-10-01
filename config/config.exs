# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :viewninjas, :scopes,
  user: [
    default: true,
    module: ViewNinjas.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ViewNinjas.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :viewninjas,
  namespace: ViewNinjas,
  ecto_repos: [ViewNinjas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :viewninjas, ViewNinjasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ViewNinjasWeb.ErrorHTML, json: ViewNinjasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ViewNinjas.PubSub,
  live_view: [signing_salt: "zt0UlJkB"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :viewninjas, ViewNinjas.Mailer, adapter: Swoosh.Adapters.Local

# The From address on transactional email. Overridable per environment (see
# config/runtime.exs) so the placeholder domain never ships.
config :viewninjas, :mailer_from, {"Tangi", "no-reply@example.com"}

# Outbound SMS. Development logs the message (so an OTP is visible locally),
# production uses Africa's Talking, tests use an in-memory outbox. The daily
# spend cap is a hard stop: SMS pumping is a top-three fraud risk in Kenya.
config :viewninjas, :sms,
  provider: ViewNinjas.Sms.Providers.Log,
  daily_cap_micros: 20_000_000,
  estimated_cost_micros: 800_000

# The wholesale panels (scope.md §5, §9). Adding a fourth panel that speaks the
# same v2 dialect is a row plus a key, so the panel list is config, not code;
# capabilities are data the UI reads, not branches in the client.
config :viewninjas, :suppliers,
  # A panel whose balance drops under this USD floor (in micros) is paused and
  # alerted, so a lane on it stops selling before a customer pays (scope.md §10).
  low_balance_micros: 5_000_000,
  panels: [
    %{
      slug: "secsers",
      base_url: "https://secsers.com/api/v2",
      capabilities: %{
        "services" => true,
        "add" => true,
        "status" => true,
        "balance" => true,
        "refill" => true,
        "refill_status" => true,
        "cancel" => false,
        "multi_status_limit" => 100
      }
    },
    %{
      slug: "jap",
      base_url: "https://justanotherpanel.com/api/v2",
      capabilities: %{
        "services" => true,
        "add" => true,
        "status" => true,
        "balance" => true,
        "refill" => true,
        "refill_status" => true,
        "cancel" => true,
        "multi_status_limit" => 100
      }
    },
    %{
      slug: "smmfollows",
      base_url: "https://smmfollows.io/api/v2",
      capabilities: %{
        "services" => true,
        "add" => true,
        "status" => true,
        "balance" => true,
        "refill" => true,
        "refill_status" => true,
        "cancel" => true,
        "multi_status_limit" => 100
      }
    }
  ]

# Configure Oban. Every job that talks to the outside world (supplier sync,
# payments, FX refresh, low-balance alerts) runs here and nowhere else, so a
# rendered page can never trigger an outbound call.
config :viewninjas, Oban,
  repo: ViewNinjas.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    # The daily USD->KES rate. It is a no-op until FX_SOURCE_URL names a provider.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 4 * * *", ViewNinjas.Workers.FetchFxRate},
       # The backstop for a dropped payment callback (docs/malipo-connect.md §9).
       {"* * * * *", ViewNinjas.Workers.SweepPendingPayments},
       # Every order still moving, checked with its panel (scope.md §10).
       {"* * * * *", ViewNinjas.Workers.SyncOrderStatuses},
       # Refills that have not yet resolved (scope.md §10).
       {"* * * * *", ViewNinjas.Workers.SyncRefillStatuses},
       # The first-party anomaly pass: settlements, failures, OTP, margin, traffic.
       {"0 * * * *", ViewNinjas.Workers.CheckAnomalies},
       # Yesterday's rollup, once the day is over (scope.md §11).
       {"10 0 * * *", ViewNinjas.Workers.RollupDaily},
       # The Sunday message to the super-admin (scope.md §11).
       {"0 21 * * 0", ViewNinjas.Workers.WeeklyDigest}
     ]}
  ],
  queues: [default: 10, payments: 10]

# The payment rail (scope.md §8). Malipo everywhere but tests, which use an
# in-memory stand-in so nothing reaches the network.
config :viewninjas, :payments, provider: ViewNinjas.Payments.Malipo

# Client config for the Malipo rail; the key itself comes from the environment at
# runtime, so no secret is ever in the repo.
config :viewninjas, ViewNinjas.Payments.Malipo,
  base_url: "https://backend.kioskpay.co.ke",
  create_path: "/v1/payments",
  check_path: "/v1/payments/{id}"

# Client config for the airtime rail (docs/instalipa-airtime.md). Same rule: the
# consumer key and secret come from the environment at runtime or the back office,
# so no secret is ever in the repo.
config :viewninjas, ViewNinjas.Airtime.Instalipa,
  base_url: "https://business.instalipa.co.ke",
  token_path: "/api/v1/token",
  airtime_path: "/api/v1/airtime",
  status_path: "/api/v1/status/{id}"

# The pricing knobs live in the database, not config (scope.md §7). Only the FX
# source the daily job reads is configured here; with no URL the job no-ops.
config :viewninjas, :pricing,
  fx_source_url: nil,
  fx_source_path: "rates.KES"

# First-party analytics (scope.md §13). The visitor hash is salted with this and
# the day, so it rotates daily; an environment-provided salt is used in
# production, and the development value is never a secret worth keeping.
config :viewninjas, :insight, hash_salt: "viewninjas-dev-salt"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  viewninjas: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# The Cloak vault encrypts supplier API keys at rest (scope.md §12). This key
# is the development one; production sets CLOAK_KEY (see config/runtime.exs).
# Generate a new one with:
#
#     elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
config :viewninjas, ViewNinjas.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("frchBo0ZWAE+4Go3hdV1JAhiDtSNId3JjxdGE7Vm2No="),
      iv_length: 12
    }
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Sentry (error reporting) reports through the app's shared Finch pool rather
# than bundling Hackney. It is inert unless a DSN is configured at runtime.
config :sentry, client: ViewNinjas.SentryFinchClient

# Rate limiting is on everywhere except tests, which turn it off so unrelated
# cases do not share one budget (the rate-limit tests switch it back on).
config :viewninjas, rate_limiting: true

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
