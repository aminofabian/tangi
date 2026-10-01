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

  @default_mailer_from {"Tangi", "no-reply@example.com"}
  @default_resend_base_url "https://api.resend.com"

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
      key: "malipo_client_id",
      group: "Payments",
      label: "Client ID",
      placeholder: "pk_live_…",
      hint: "The client id Connect shows (pk_live_…). It is not the payment key and is not sent.",
      env: {:malipo, :client_id}
    },
    %{
      key: "malipo_base_url",
      group: "Payments",
      label: "Endpoint base URL",
      placeholder: "https://backend.kioskpay.co.ke",
      hint:
        "The host Connect shows. Create and check are joined onto this unless they are full URLs.",
      env: {:malipo, :base_url},
      default: "https://backend.kioskpay.co.ke"
    },
    %{
      key: "malipo_create_path",
      group: "Payments",
      label: "Create a payment",
      placeholder: "/v1/payments",
      hint: "POST path, or a full https URL. Default /v1/payments.",
      env: {:malipo, :create_path},
      default: "/v1/payments"
    },
    %{
      key: "malipo_check_path",
      group: "Payments",
      label: "Check a payment",
      placeholder: "/v1/payments/{id}",
      hint: "GET path. {id} is the payment id. Default /v1/payments/{id}.",
      env: {:malipo, :check_path},
      default: "/v1/payments/{id}"
    },
    %{
      key: "malipo_secret_key",
      group: "Payments",
      label: "Secret key",
      secret: true,
      hint:
        "Required. The key in Connect's sample request, starting with sk_live_. This is the bearer.",
      env: {:malipo, :secret_key}
    },
    %{
      key: "malipo_webhook_secret",
      group: "Payments",
      label: "Webhook signing secret",
      secret: true,
      hint: "Optional whsec_… secret. Leave blank to confirm payments by checking them.",
      env: {:viewninjas, :malipo_webhook_secret}
    },
    %{
      key: "instalipa_base_url",
      group: "Airtime",
      label: "Endpoint base URL",
      placeholder: "https://business.instalipa.co.ke",
      hint: "The host Instalipa gives you. Token, send and status are joined onto it.",
      env: {:instalipa, :base_url},
      default: "https://business.instalipa.co.ke"
    },
    %{
      key: "instalipa_token_path",
      group: "Airtime",
      label: "Access token path",
      placeholder: "/api/v1/token",
      hint: "POST path, or a full https URL. Default /api/v1/token.",
      env: {:instalipa, :token_path},
      default: "/api/v1/token"
    },
    %{
      key: "instalipa_airtime_path",
      group: "Airtime",
      label: "Send airtime path",
      placeholder: "/api/v1/airtime",
      hint: "POST path, or a full https URL. Default /api/v1/airtime.",
      env: {:instalipa, :airtime_path},
      default: "/api/v1/airtime"
    },
    %{
      key: "instalipa_status_path",
      group: "Airtime",
      label: "Transaction status path",
      placeholder: "/api/v1/status/{id}",
      hint: "GET path. {id} is replaced. Default /api/v1/status/{id}.",
      env: {:instalipa, :status_path},
      default: "/api/v1/status/{id}"
    },
    %{
      key: "instalipa_consumer_key",
      group: "Airtime",
      label: "Consumer key",
      secret: true,
      hint: "Required. The consumer key from the Instalipa app's API credentials.",
      env: {:instalipa, :consumer_key}
    },
    %{
      key: "instalipa_consumer_secret",
      group: "Airtime",
      label: "Consumer secret",
      secret: true,
      hint: "Required. Shown once in the portal; regenerate if lost.",
      env: {:instalipa, :consumer_secret}
    },
    %{
      key: "airtime_float_floor_cents",
      group: "Airtime",
      label: "Float floor (KES cents)",
      type: :integer,
      hint:
        "Selling stops when the balance Instalipa reports falls below this. Default 500000 (KSh 5,000). Keeps an empty float from becoming a queue of refunds.",
      env: {:instalipa, :float_floor_cents},
      default: 500_000
    },
    %{
      key: "airtime_float_manual_cents",
      group: "Airtime",
      label: "Float, entered by hand (KES cents)",
      type: :integer,
      hint:
        "The balance shown in the Instalipa portal. Enter it after topping up. Instalipa has no balance endpoint, so this is the only way the system can learn a float it did not read from a send. Clear it to go back to reading the rail.",
      env: {:instalipa, :float_manual_cents}
    },
    %{
      key: "airtime_float_max_age_minutes",
      group: "Airtime",
      label: "Float reading lifetime (minutes)",
      type: :integer,
      hint:
        "A rail reading older than this stops holding selling off, because we cannot refresh it while selling is stopped. Default 60. Leave the floor generous rather than setting this low.",
      env: {:instalipa, :float_max_age_minutes},
      default: 60
    },
    %{
      key: "instalipa_paused",
      group: "Airtime",
      label: "Selling paused",
      hint:
        "Type \"true\" to stop selling airtime by hand. Clear it to resume. The buy screen refuses before taking money while this is on.",
      env: {:instalipa, :paused}
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
      hint:
        "The From on every email. Resend only sends from a domain you have verified, so use that domain here.",
      env: {:mailer, :from}
    },
    %{
      key: "resend_api_key",
      group: "Mail",
      label: "Resend API key",
      secret: true,
      placeholder: "re_…",
      hint:
        "Required to send email. From Resend → API Keys. Stored encrypted and never shown back; saving a new one takes effect on the next send.",
      env: {:resend, :api_key}
    },
    %{
      key: "resend_base_url",
      group: "Mail",
      label: "Resend API base URL",
      placeholder: "https://api.resend.com",
      hint: "Leave as the default unless you are pointed at a test endpoint.",
      env: {:resend, :base_url},
      default: @default_resend_base_url
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
    |> Map.put(:value, if(secret?, do: nil, else: shown_value(spec, stored, override)))
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

  @doc "The Malipo client id (`pk_live_…`)."
  @spec malipo_client_id() :: String.t() | nil
  def malipo_client_id, do: resolved_value("malipo_client_id")

  @doc "The Malipo secret key."
  @spec malipo_secret_key() :: String.t() | nil
  def malipo_secret_key, do: resolved_value("malipo_secret_key")

  @doc "The Malipo base URL."
  @spec malipo_base_url() :: String.t()
  def malipo_base_url, do: resolved_value("malipo_base_url")

  @doc "Path or absolute URL for POST /v1/payments."
  @spec malipo_create_path() :: String.t()
  def malipo_create_path, do: resolved_value("malipo_create_path")

  @doc "Path or absolute URL for GET /v1/payments/{id}. `{id}` is replaced."
  @spec malipo_check_path() :: String.t()
  def malipo_check_path, do: resolved_value("malipo_check_path")

  @doc "The Malipo webhook signing secret, or nil when callbacks are unsigned."
  @spec malipo_webhook_secret() :: String.t() | nil
  def malipo_webhook_secret, do: resolved_value("malipo_webhook_secret")

  @doc "The Instalipa base URL."
  @spec instalipa_base_url() :: String.t()
  def instalipa_base_url, do: resolved_value("instalipa_base_url")

  @doc "Path or absolute URL for POST the access token."
  @spec instalipa_token_path() :: String.t()
  def instalipa_token_path, do: resolved_value("instalipa_token_path")

  @doc "Path or absolute URL for POST airtime."
  @spec instalipa_airtime_path() :: String.t()
  def instalipa_airtime_path, do: resolved_value("instalipa_airtime_path")

  @doc "Path or absolute URL for GET a transaction status. `{id}` is replaced."
  @spec instalipa_status_path() :: String.t()
  def instalipa_status_path, do: resolved_value("instalipa_status_path")

  @doc "The Instalipa consumer key."
  @spec instalipa_consumer_key() :: String.t() | nil
  def instalipa_consumer_key, do: resolved_value("instalipa_consumer_key")

  @doc "The Instalipa consumer secret."
  @spec instalipa_consumer_secret() :: String.t() | nil
  def instalipa_consumer_secret, do: resolved_value("instalipa_consumer_secret")

  @doc """
  Whether airtime selling is paused by hand (docs/instalipa-airtime.md §10).

  The kill switch: one tap stops the line taking money, whatever the rail says.
  """
  @spec instalipa_paused?() :: boolean()
  def instalipa_paused?, do: truthy?(resolved_value("instalipa_paused"))

  @doc """
  A float the super-admin typed in from the Instalipa portal, or nil.

  Instalipa has **no balance endpoint** (scope §10), so the only reading we ever get
  for free is the `balance` on a send response. Once the floor stops selling, no send
  happens, so no reading ever arrives — a float we topped up externally is invisible
  to us. This is the escape hatch §10 asks for, and without it a low reading is a
  one-way door.
  """
  @spec airtime_float_manual_cents() :: integer() | nil
  def airtime_float_manual_cents do
    case resolved_value("airtime_float_manual_cents") do
      nil -> nil
      value -> parse_integer(value)
    end
  end

  @doc "How long a rail float reading stays believable, in minutes."
  @spec airtime_float_max_age_minutes() :: pos_integer()
  def airtime_float_max_age_minutes do
    resolved_value("airtime_float_max_age_minutes") |> parse_integer() || 60
  end

  @doc "The float floor in cents. Selling stops below it."
  @spec airtime_float_floor_cents() :: integer()
  def airtime_float_floor_cents do
    resolved_value("airtime_float_floor_cents") |> parse_integer() || 500_000
  end

  @doc "The daily FX feed URL, or nil when there is none."
  @spec fx_source_url() :: String.t() | nil
  def fx_source_url, do: resolved_value("fx_source_url")

  @doc "The JSON path to the rate inside the FX feed."
  @spec fx_source_path() :: String.t()
  def fx_source_path, do: resolved_value("fx_source_path")

  @doc "The salt the visitor hash rotates on."
  @spec insight_hash_salt() :: String.t()
  def insight_hash_salt, do: resolved_value("insight_hash_salt")

  @doc """
  The From address on transactional email, as `{name, address}`.
  """
  @spec mailer_from() :: {String.t(), String.t()}
  def mailer_from do
    case value("mailer_from") do
      nil -> Application.get_env(:viewninjas, :mailer_from, @default_mailer_from)
      address -> {"Tangi", address}
    end
  end

  @doc "The Resend API key, or nil when email is not configured."
  @spec resend_api_key() :: String.t() | nil
  def resend_api_key, do: resolved_value("resend_api_key")

  @doc "The Resend API base URL."
  @spec resend_base_url() :: String.t()
  def resend_base_url, do: resolved_value("resend_base_url")

  @doc "Whether a Resend key is in force, so email is worth attempting."
  @spec email_configured?() :: boolean()
  def email_configured?, do: present?(resend_api_key())

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
  defp from_env(%{env: {:instalipa, key}}), do: instalipa_env(key)
  defp from_env(%{env: {:resend, key}}), do: env(:resend, key)
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

  # The screen shows the value in force, so a default is an editable field rather
  # than a blank box. A stored override wins.
  defp shown_value(_spec, _stored, override) when is_binary(override) and override != "",
    do: override

  defp shown_value(spec, stored, _override), do: resolved(spec, stored) || ""

  defp stringify(nil), do: nil
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value), do: to_string(value)

  # Application env is normally a keyword list, but `Application.put_env/3` will
  # happily store nil for "unset this", and a nil here would crash every settings
  # read. Treat anything that is not a keyword list as no environment value.
  defp env(app_key, key) do
    case Application.get_env(:viewninjas, app_key) do
      config when is_list(config) -> Keyword.get(config, key)
      _other -> nil
    end
  end

  defp malipo_env(key),
    do: :viewninjas |> Application.get_env(ViewNinjas.Payments.Malipo, []) |> Keyword.get(key)

  defp instalipa_env(key),
    do: :viewninjas |> Application.get_env(ViewNinjas.Airtime.Instalipa, []) |> Keyword.get(key)

  defp present?(value), do: is_binary(value) and value != ""

  # A hand-set toggle, so the words a person would type are all accepted.
  defp truthy?(value) when is_binary(value),
    do: String.downcase(String.trim(value)) in ["true", "1", "yes", "on"]

  defp truthy?(_value), do: false

  defp group_order("SMS"), do: 0
  defp group_order("Payments"), do: 1
  defp group_order("Airtime"), do: 2
  defp group_order("Pricing"), do: 3
  defp group_order("Insight"), do: 4
  defp group_order("Mail"), do: 5
  defp group_order(_other), do: 99
end
