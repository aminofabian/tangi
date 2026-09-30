import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :viewninjas, ViewNinjas.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "viewninjas_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  # LiveViews and Oban workers share the sandbox's connections, so wait longer
  # rather than dropping a request when the suite is running many cases at once.
  queue_target: 500,
  queue_interval: 5_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :viewninjas, ViewNinjasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JOWsWdgXuPPBZ+YKwqXBzQtKv3eBPeAAqWKjToHOpD+8uiG+bDGUA8UQZDobOUG9",
  server: false

# In test we don't send emails
config :viewninjas, ViewNinjas.Mailer, adapter: Swoosh.Adapters.Test

# SMS goes to an in-memory outbox so tests can read the OTP and assert on it.
config :viewninjas, :sms, provider: ViewNinjas.Sms.Providers.Test

# The payment rail is an in-memory stand-in in tests, so no test ever prompts a
# real phone or reaches the network.
config :viewninjas, :payments, provider: ViewNinjas.Payments.Providers.Test

# Run Oban jobs inline only when a test explicitly executes them, so tests
# stay deterministic and never hit the network by accident. No cron in tests.
config :viewninjas, Oban, testing: :manual, plugins: [Oban.Plugins.Pruner]

# Rate limiting stays on in tests so the real path is exercised, but with
# generous limits so unrelated cases never trip a budget. The dedicated
# rate-limit test tightens these for the duration of its own assertions.
config :viewninjas, rate_limiting: true

config :viewninjas,
  rate_limits: %{
    signup_ip: {3_600_000, 1_000},
    signup_phone: {3_600_000, 1_000},
    login_ip: {300_000, 1_000},
    login_identifier: {300_000, 1_000},
    otp_ip: {3_600_000, 1_000},
    otp_phone: {3_600_000, 1_000},
    payment_user: {3_600_000, 1_000},
    payment_phone: {3_600_000, 1_000}
  }

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
