defmodule ViewNinjas.Settings do
  @moduledoc """
  Operational settings the super-admin sets in the back office (scope.md §7, §11).

  One row per key, **encrypted at rest** with the Vault, with the person who last
  changed it. A value is read at call time: the database first, then the
  environment (`config/runtime.exs`), then the default below — so an environment
  value keeps working and the super-admin can override it without a redeploy.

  A handful of values must stay in the environment, because they are needed
  **before the database is reachable** or because they decrypt this table itself:
  `DATABASE_URL` and the `POSTGRES_*` variables, `SECRET_KEY_BASE`, `CLOAK_KEY`,
  `PORT`, `PHX_HOST`, the Sentry DSN and the mailer adapter. Everything registered
  here is the super-admin's to set.
  """

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Repo
  alias ViewNinjas.Settings.Setting

  @default_mailer_from {"ViewNinjas", "no-reply@example.com"}

  # The registry: what the screen shows, where the value comes from, and how a
  # submission is read back. `env` names the environment fallback; `default` is
  # used when neither the database nor the environment has one; `secret` decides
  # whether the back office masks it.
  @specs [
    %{
      key: "textsms_api_key",
      group: "SMS",
      label: "TextSMS API key",
      secret: true,
      env: {:sms, :api_key}
    },
    %{
      key: "textsms_partner_id",
      group: "SMS",
      label: "TextSMS partner id",
      secret: true,
      env: {:sms, :partner_id}
    },
    %{
      key: "textsms_shortcode",
      group: "SMS",
      label: "TextSMS shortcode",
      env: {:sms, :shortcode}
    },
    %{
      key: "sms_daily_cap_micros",
      group: "SMS",
      label: "Daily SMS cap (micros of KES)",
      type: :integer,
      env: {:sms, :daily_cap_micros},
      default: 20_000_000
    },
    %{
      key: "malipo_base_url",
      group: "Payments",
      label: "Malipo base URL",
      env: {:malipo, :base_url},
      default: "https://api.kiosk.ke"
    },
    %{
      key: "malipo_secret_key",
      group: "Payments",
      label: "Malipo secret key",
      secret: true,
      env: {:malipo, :secret_key}
    },
    %{
      key: "malipo_webhook_secret",
      group: "Payments",
      label: "Malipo webhook signing secret",
      secret: true,
      env: {:viewninjas, :malipo_webhook_secret}
    },
    %{
      key: "fx_source_url",
      group: "Pricing",
      label: "FX source URL",
      env: {:pricing, :fx_source_url}
    },
    %{
      key: "fx_source_path",
      group: "Pricing",
      label: "FX JSON path (e.g. rates.KES)",
      env: {:pricing, :fx_source_path},
      default: "rates.KES"
    },
    %{
      key: "insight_hash_salt",
      group: "Insight",
      label: "Visitor-hash salt",
      secret: true,
      env: {:insight, :hash_salt},
      default: "viewninjas"
    },
    %{
      key: "mailer_from",
      group: "Mail",
      label: "Mailer From address",
      env: {:mailer, :from}
    }
  ]

  @doc "The registered settings, in display order."
  @spec specs() :: [map()]
  def specs, do: @specs

  @doc "The settings grouped for the screen: `[{group, [spec]}]`."
  @spec groups() :: [{String.t(), [map()]}]
  def groups do
    @specs
    |> Enum.group_by(& &1.group)
    |> Enum.map(fn {group, specs} -> {group, specs} end)
    |> Enum.sort_by(fn {group, _specs} -> group_order(group) end)
  end

  @doc """
  Each setting with its current state for the screen.

  `stored` is whether this back office has an override; `effective` is whether a
  value is in force at all (an override, the environment, or the default). A
  secret's value is **never** returned — the form leaves it alone unless a new one
  is typed.
  """
  @spec entries() :: [map()]
  def entries do
    stored = stored_settings()

    Enum.map(@specs, fn spec -> entry(spec, stored) end)
  end

  defp entry(spec, stored) do
    secret? = spec[:secret] == true
    override = Map.get(stored, spec.key)

    spec
    |> Map.put(:secret, secret?)
    |> Map.put(:stored, present?(override))
    |> Map.put(:effective, present?(resolved(spec, stored)))
    |> Map.put(:value, if(secret?, do: nil, else: override || ""))
  end

  @doc """
  Every stored override as `%{key => value}` (decrypted).

  Before the repo is up — during application start, when the SMS and payment
  providers are chosen — there are no overrides to read yet, so this is empty and
  the environment decides. That is why a settings read never crashes a boot.
  """
  @spec stored_settings() :: %{String.t() => String.t() | nil}
  def stored_settings do
    if Process.whereis(Repo) do
      Setting
      |> Repo.all()
      |> Map.new(&{&1.key, &1.value})
    else
      %{}
    end
  end

  @doc "Writes one setting, recording who changed it."
  @spec put(String.t() | atom(), String.t(), User.t() | nil) ::
          {:ok, Setting.t()}
          | {:error, :unknown_key | :not_an_integer | Ecto.Changeset.t()}
  def put(key, value, actor) do
    key = to_string(key)

    with {:ok, spec} <- fetch_spec(key),
         {:ok, value} <- read_value(spec, value) do
      attrs = %{
        key: key,
        value: value,
        secret: spec[:secret] == true,
        updated_by_id: actor && actor.id
      }

      case Repo.get_by(Setting, key: key) do
        nil -> %Setting{} |> Setting.changeset(attrs) |> Repo.insert()
        setting -> setting |> Setting.changeset(attrs) |> Repo.update()
      end
    end
  end

  @doc """
  Writes every setting submitted with a non-blank value.

  A blank field means "leave it as it is", so a form never wipes a secret by
  accident. Returns how many were written.
  """
  @spec put_many(map(), User.t() | nil) :: {:ok, non_neg_integer()} | {:error, term()}
  def put_many(params, actor) when is_map(params) do
    Enum.reduce_while(@specs, {:ok, 0}, fn spec, acc -> put_one(spec, params, actor, acc) end)
  end

  defp put_one(spec, params, actor, {:ok, count}) do
    case submitted(params, spec.key) do
      nil -> {:cont, {:ok, count}}
      value -> step(put(spec.key, value, actor), count)
    end
  end

  defp step({:ok, _setting}, count), do: {:cont, {:ok, count + 1}}
  defp step(error, _count), do: {:halt, error}

  @doc "Removes an override, so the environment or the default applies again."
  @spec clear(String.t() | atom()) :: :ok
  def clear(key) do
    case Repo.get_by(Setting, key: to_string(key)) do
      nil ->
        :ok

      setting ->
        {:ok, _deleted} = Repo.delete(setting)
        :ok
    end
  end

  # -- the values the app reads ------------------------------------------

  @doc "The TextSMS API key."
  @spec textsms_api_key() :: String.t() | nil
  def textsms_api_key, do: resolved_value("textsms_api_key")

  @doc "The TextSMS partner id."
  @spec textsms_partner_id() :: String.t() | nil
  def textsms_partner_id, do: resolved_value("textsms_partner_id")

  @doc "The TextSMS shortcode, when the sender must be one."
  @spec textsms_shortcode() :: String.t() | nil
  def textsms_shortcode, do: resolved_value("textsms_shortcode")

  @doc "The endpoint TextSMS is reached at (environment-only; more than one host exists)."
  @spec textsms_endpoint() :: String.t() | nil
  def textsms_endpoint, do: env(:sms, :endpoint)

  @doc "Whether the SMS rail is configured well enough to try."
  @spec textsms_configured?() :: boolean()
  def textsms_configured?, do: present?(textsms_api_key()) and present?(textsms_partner_id())

  @doc "The daily SMS cap in micros of KES."
  @spec sms_daily_cap_micros() :: pos_integer()
  def sms_daily_cap_micros do
    resolved_value("sms_daily_cap_micros") |> parse_integer() || 20_000_000
  end

  @doc "The Malipo secret key."
  @spec malipo_secret_key() :: String.t() | nil
  def malipo_secret_key, do: resolved_value("malipo_secret_key")

  @doc "The Malipo base URL."
  @spec malipo_base_url() :: String.t()
  def malipo_base_url, do: resolved_value("malipo_base_url")

  @doc "The Malipo webhook signing secret, or nil when callbacks are unsigned."
  @spec malipo_webhook_secret() :: String.t() | nil
  def malipo_webhook_secret, do: resolved_value("malipo_webhook_secret")

  @doc "The daily FX feed URL, or nil when there is none."
  @spec fx_source_url() :: String.t() | nil
  def fx_source_url, do: resolved_value("fx_source_url")

  @doc "The JSON path to the rate inside the FX feed."
  @spec fx_source_path() :: String.t()
  def fx_source_path, do: resolved_value("fx_source_path")

  @doc "The salt the visitor hash rotates on."
  @spec insight_hash_salt() :: String.t()
  def insight_hash_salt, do: resolved_value("insight_hash_salt")

  @doc "The From address on transactional email, as `{name, address}`."
  @spec mailer_from() :: {String.t(), String.t()}
  def mailer_from do
    case value("mailer_from") do
      nil -> Application.get_env(:viewninjas, :mailer_from, @default_mailer_from)
      address -> {"ViewNinjas", address}
    end
  end

  # -- internals ---------------------------------------------------------

  defp resolved_value(key), do: resolved(spec!(key), stored_settings())

  # Database, then the environment, then the default.
  defp resolved(spec, stored) do
    Map.get(stored, spec.key) || from_env(spec) || stringify(spec[:default])
  end

  defp from_env(%{env: {:sms, key}}), do: env(:sms, key)
  defp from_env(%{env: {:pricing, key}}), do: env(:pricing, key)
  defp from_env(%{env: {:insight, key}}), do: env(:insight, key)
  defp from_env(%{env: {:malipo, key}}), do: malipo_env(key)
  defp from_env(%{env: {:viewninjas, key}}), do: Application.get_env(:viewninjas, key)

  defp from_env(%{env: {:mailer, :from}}) do
    :viewninjas |> Application.get_env(:mailer_from, @default_mailer_from) |> elem(1)
  end

  defp from_env(_spec), do: nil

  defp value(key), do: Map.get(stored_settings(), key)

  defp spec!(key) do
    case fetch_spec(key) do
      {:ok, spec} -> spec
      {:error, :unknown_key} -> raise ArgumentError, "unknown setting: #{inspect(key)}"
    end
  end

  defp fetch_spec(key) do
    case Enum.find(@specs, &(&1.key == to_string(key))) do
      nil -> {:error, :unknown_key}
      spec -> {:ok, spec}
    end
  end

  defp read_value(%{type: :integer}, value) do
    case parse_integer(value) do
      nil -> {:error, :not_an_integer}
      integer -> {:ok, Integer.to_string(integer)}
    end
  end

  defp read_value(_spec, value), do: {:ok, String.trim(value)}

  defp submitted(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> nil
      value when is_binary(value) -> String.trim(value)
      value -> to_string(value)
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_value), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value), do: to_string(value)

  defp env(app_key, key), do: :viewninjas |> Application.get_env(app_key, []) |> Keyword.get(key)

  defp malipo_env(key),
    do: :viewninjas |> Application.get_env(ViewNinjas.Payments.Malipo, []) |> Keyword.get(key)

  defp present?(value), do: is_binary(value) and value != ""

  defp group_order("SMS"), do: 0
  defp group_order("Payments"), do: 1
  defp group_order("Pricing"), do: 2
  defp group_order("Insight"), do: 3
  defp group_order("Mail"), do: 4
  defp group_order(_other), do: 99
end
