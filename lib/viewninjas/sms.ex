defmodule ViewNinjas.Sms do
  @moduledoc """
  Outbound SMS: one row per message, one provider call, and a daily spend cap
  (build-plan.md M2, scope.md §13).

  Every outbound SMS goes through here, and the callers are Oban workers — a
  rendered page never makes the request itself (scope.md §13). The daily cap
  is checked before sending and refuses with a loud alert, because SMS pumping
  is a top-three fraud risk in this market.
  """
  import Ecto.Query

  require Logger

  alias ViewNinjas.Repo
  alias ViewNinjas.Settings
  alias ViewNinjas.Sms.SmsMessage

  # What a message is assumed to cost when no cost has been reported yet, so a
  # burst of queued messages still counts against the cap (KES 0.80).
  @default_estimated_cost_micros 800_000

  @doc """
  Sends one SMS and records it either way.

  Returns `{:ok, message}` with the provider reference and cost filled in, or
  `{:error, :spend_cap_reached}` when the day's budget is gone.
  """
  @spec send_message(%{to: String.t(), template: String.t(), body: String.t()}) ::
          {:ok, SmsMessage.t()} | {:error, term()}
  def send_message(%{to: to, template: template, body: body}) do
    if within_daily_cap?() do
      message = insert_message!(to, template)

      case provider().send_sms(to, body) do
        {:ok, result} -> {:ok, update_message!(message, result)}
        {:error, reason} -> {:error, reason}
      end
    else
      alert(:daily_cap_reached)
      {:error, :spend_cap_reached}
    end
  end

  @doc """
  Records a delivery report from the provider, matched on the stored reference.
  """
  @spec record_delivery(String.t(), atom()) :: {:ok, SmsMessage.t()} | {:error, :not_found}
  def record_delivery(provider_ref, status) when is_binary(provider_ref) do
    case Repo.get_by(SmsMessage, provider_ref: provider_ref) do
      nil -> {:error, :not_found}
      message -> {:ok, update_message!(message, %{status: status})}
    end
  end

  @doc """
  Today's spend in micros of KES. Messages whose cost is not known yet count at
  the estimated cost, so the cap is not defeated by a burst of pending sends.
  """
  @spec spent_today_micros() :: non_neg_integer()
  def spent_today_micros do
    start_of_day = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    estimate = estimated_cost_micros()

    Repo.one(
      from m in SmsMessage,
        where: m.inserted_at >= ^start_of_day,
        select: coalesce(sum(coalesce(m.cost_micros, ^estimate)), 0)
    )
  end

  @doc "Whether today's spend is still under the cap."
  @spec within_daily_cap?() :: boolean()
  def within_daily_cap?, do: spent_today_micros() < daily_cap_micros()

  @doc "How many messages went out today, for the dashboard and the spike alert."
  @spec count_today() :: non_neg_integer()
  def count_today do
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    Repo.one(from m in SmsMessage, where: m.inserted_at >= ^start, select: count(m.id))
  end

  @doc "How many messages were recorded in a window."
  @spec count_between(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def count_between(from, to) do
    Repo.one(
      from m in SmsMessage,
        where: m.inserted_at >= ^from and m.inserted_at < ^to,
        select: count(m.id)
    )
  end

  @spec daily_cap_micros() :: non_neg_integer()
  def daily_cap_micros, do: Settings.sms_daily_cap_micros()

  @spec estimated_cost_micros() :: non_neg_integer()
  def estimated_cost_micros,
    do: sms_config(:estimated_cost_micros, @default_estimated_cost_micros)

  @doc """
  The provider in force: the configured one, unless a TextSMS key has been set in
  the back office, in which case the real rail is used (development included).
  """
  @spec provider() :: module()
  def provider do
    configured = sms_config(:provider, ViewNinjas.Sms.Providers.Log)

    cond do
      configured == ViewNinjas.Sms.Providers.Test -> configured
      Settings.textsms_configured?() -> ViewNinjas.Sms.Providers.TextSms
      true -> configured
    end
  end

  @doc "A short provider name stored on the row, e.g. `\"textsms\"`."
  @spec provider_name() :: String.t()
  def provider_name do
    provider()
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  @doc """
  Raises an alert that a human should see: the log line always, and Sentry when
  it is configured.
  """
  @spec alert(atom() | String.t()) :: :ok
  def alert(reason) do
    Logger.error(
      "SMS alert: #{reason} (today #{spent_today_micros()} of #{daily_cap_micros()} micros)"
    )

    if Code.ensure_loaded?(Sentry) and Application.get_env(:sentry, :dsn) do
      Sentry.capture_message("SMS alert: #{reason}")
    end

    :ok
  end

  defp insert_message!(to, template) do
    %SmsMessage{}
    |> SmsMessage.changeset(%{
      to: to,
      template: template,
      provider: provider_name(),
      status: :queued
    })
    |> Repo.insert!()
  end

  defp update_message!(message, attrs) do
    message
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  defp sms_config(key, default) do
    :viewninjas
    |> Application.get_env(:sms, [])
    |> Keyword.get(key, default)
  end
end
