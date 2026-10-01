import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/viewninjas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :viewninjas, ViewNinjasWeb.Endpoint, server: true
end

config :viewninjas, ViewNinjasWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# TextSMS credentials come from the environment, never the repo. When an API
# key is present we use the real provider; when it is not, development keeps
# the logging provider and production fails the call with `:sms_not_configured`
# rather than putting an OTP in the logs. Tests use their own provider.
if config_env() != :test do
  config :viewninjas, :sms,
    api_key: System.get_env("TEXTSMS_API_KEY"),
    partner_id: System.get_env("TEXTSMS_PARTNER_ID"),
    shortcode: System.get_env("TEXTSMS_SHORTCODE")

  if System.get_env("TEXTSMS_API_KEY") do
    config :viewninjas, :sms, provider: ViewNinjas.Sms.Providers.TextSms
  end

  if cap = System.get_env("SMS_DAILY_CAP_MICROS") do
    config :viewninjas, :sms, daily_cap_micros: String.to_integer(cap)
  end

  # The daily FX source. With no URL the job is a no-op and the app prices from
  # the last recorded rate or the §7 default (scope.md §7).
  if url = System.get_env("FX_SOURCE_URL") do
    config :viewninjas, :pricing, fx_source_url: url
  end

  if path = System.get_env("FX_SOURCE_PATH") do
    config :viewninjas, :pricing, fx_source_path: path
  end

  # The analytics visitor-hash salt; keep it stable per deployment so hashes are
  # comparable within a day and different across days (scope.md §13).
  if salt = System.get_env("INSIGHT_HASH_SALT") do
    config :viewninjas, :insight, hash_salt: salt
  end

  # The Malipo rail (scope.md §8). With no key the client reports
  # `:not_configured` rather than prompting; the base URL can be pointed at a
  # sandbox.
  config :viewninjas, ViewNinjas.Payments.Malipo,
    base_url: System.get_env("MALIPO_BASE_URL", "https://backend.kioskpay.co.ke"),
    secret_key: System.get_env("MALIPO_SECRET_KEY"),
    client_id: System.get_env("MALIPO_CLIENT_ID"),
    create_path: System.get_env("MALIPO_CREATE_PATH", "/v1/payments"),
    check_path: System.get_env("MALIPO_CHECK_PATH", "/v1/payments/{id}")

  # Optional: when set, a Malipo callback must carry a matching signature.
  config :viewninjas, :malipo_webhook_secret, System.get_env("MALIPO_WEBHOOK_SECRET")

  # The airtime rail (docs/instalipa-airtime.md). With no consumer key and secret
  # the client reports `:not_configured` rather than sending; the base URL can be
  # pointed at a sandbox. The credentials can also be set in the back office.
  config :viewninjas, ViewNinjas.Airtime.Instalipa,
    base_url: System.get_env("INSTALIPA_BASE_URL", "https://business.instalipa.co.ke"),
    token_path: System.get_env("INSTALIPA_TOKEN_PATH", "/api/v1/token"),
    airtime_path: System.get_env("INSTALIPA_AIRTIME_PATH", "/api/v1/airtime"),
    status_path: System.get_env("INSTALIPA_STATUS_PATH", "/api/v1/status/{id}"),
    consumer_key: System.get_env("INSTALIPA_CONSUMER_KEY"),
    consumer_secret: System.get_env("INSTALIPA_CONSUMER_SECRET")

  # The airtime rail. The credentials can be set in the back office too; the
  # environment is the fallback for a first boot or a deploy pipeline.
  config :viewninjas, :resend,
    api_key: System.get_env("RESEND_API_KEY"),
    base_url: System.get_env("RESEND_BASE_URL", "https://api.resend.com")

  # Supplier API keys are encrypted with this key. Tests keep the fixed
  # development key from config/config.exs so their ciphertext is stable.
  if cloak_key = System.get_env("CLOAK_KEY") do
    config :viewninjas, ViewNinjas.Vault,
      ciphers: [
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12
        }
      ]
  end
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :viewninjas, ViewNinjasWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/viewninjas_web/router\.ex$",
        ~r"lib/viewninjas_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :viewninjas, ViewNinjas.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Supplier keys are unreadable without this, so refuse to boot without it.
  _ =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with:
          elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :viewninjas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Error reporting is enabled only when a DSN is provided, so local and CI
  # runs never try to reach Sentry and the DSN is never committed.
  if dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: dsn,
      environment_name: System.get_env("SENTRY_ENVIRONMENT") || to_string(config_env())
  end

  # Transactional email: point the mailer at a real adapter from the
  # environment, so no credentials live in the repo. Without a key the app
  # still boots and the local adapter is not used in production.
  #
  # Resend is normally configured in the back office instead (Settings), which
  # takes effect on the next send; `ViewNinjas.Email` prefers that key over
  # whatever is chosen here.
  if mailgun_key = System.get_env("MAILGUN_API_KEY") do
    config :viewninjas, ViewNinjas.Mailer,
      adapter: Swoosh.Adapters.Mailgun,
      api_key: mailgun_key,
      domain: System.get_env("MAILGUN_DOMAIN")
  end

  if from = System.get_env("MAILER_FROM") do
    config :viewninjas, :mailer_from, {"Tangi", from}
  end

  config :viewninjas, ViewNinjasWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :viewninjas, ViewNinjasWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :viewninjas, ViewNinjasWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :viewninjas, ViewNinjas.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
