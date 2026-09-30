defmodule ViewNinjas.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ViewNinjasWeb.Telemetry,
        # The vault starts before the repo so encrypted columns can be read as
        # soon as the first query runs.
        ViewNinjas.Vault,
        ViewNinjas.Repo,
        {DNSCluster, query: Application.get_env(:viewninjas, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ViewNinjas.PubSub},
        # One shared HTTP client for every outbound call (suppliers, Malipo, FX).
        # Nothing renders a page by making a request; only Oban workers call out.
        {Finch, name: ViewNinjas.Finch},
        {Oban, Application.fetch_env!(:viewninjas, Oban)},
        # In-memory rate limiter (Hammer/ETS); owns its own ETS table.
        ViewNinjas.RateLimit,
        # Start to serve requests, typically the last entry
        ViewNinjasWeb.Endpoint
      ]

    # The in-memory SMS outbox is only needed when the in-memory provider is
    # configured (tests); it owns its table so it survives the whole run.
    children =
      if ViewNinjas.Sms.provider() == ViewNinjas.Sms.Providers.Test do
        List.insert_at(children, -2, ViewNinjas.Sms.Outbox)
      else
        children
      end

    # Likewise for the in-memory payment rail used in tests.
    children =
      if ViewNinjas.Payments.provider() == ViewNinjas.Payments.Providers.Test do
        List.insert_at(children, -2, ViewNinjas.Payments.Outbox)
      else
        children
      end

    # Note: error reporting (Sentry) is its own OTP application and starts
    # automatically as a dependency; it is inert unless a DSN is configured.
    # See ViewNinjas.SentryFinchClient and config/runtime.exs.

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ViewNinjas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ViewNinjasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
