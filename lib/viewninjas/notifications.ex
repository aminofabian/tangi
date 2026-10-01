defmodule ViewNinjas.Notifications do
  @moduledoc """
  Telling the customer, without them refreshing (scope.md §11; build-plan.md M11).

  Two channels, each with a preference: a transactional SMS when an order is
  `paid`, `completed` or `refunded` (or partly delivered), and an email receipt
  carrying the M-Pesa code. Both default on; either can be turned off, and SMS
  has quiet hours — outside them the message is snoozed, not lost.

  Messages are composed here and sent from `NotifyOrder`, so a rendered page never
  makes the call (scope.md §13). Quiet hours are read in local time
  (Africa/Nairobi, UTC+3), because that is the customer's clock, not the server's.
  """

  import Ecto.Query

  require Logger

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Notifications.NotificationPreference
  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments
  alias ViewNinjas.Pricing
  alias ViewNinjas.Repo
  alias ViewNinjas.Workers.NotifyOrder

  @channels [:sms, :email]
  @events [:paid, :completed, :refunded, :partial]
  # Africa/Nairobi has no daylight saving; this is the customer's clock.
  @local_offset_seconds 3 * 3600

  @doc "The order events that are worth telling a customer about."
  @spec events() :: [atom()]
  def events, do: @events

  # -- preferences -------------------------------------------------------

  @doc "The channels a customer can be reached on."
  @spec channels() :: [atom()]
  def channels, do: @channels

  @doc "A customer's preferences, defaults filled in for anything unsaid."
  @spec preferences(User.t()) :: %{
          atom() => %{opted_in: boolean(), quiet_hours: String.t() | nil}
        }
  def preferences(%User{id: user_id}) do
    stored =
      Repo.all(from p in NotificationPreference, where: p.user_id == ^user_id)
      |> Map.new(&{&1.channel, &1})

    Map.new(@channels, fn channel ->
      case Map.get(stored, channel) do
        nil ->
          {channel, %{opted_in: true, quiet_hours: nil}}

        %NotificationPreference{} = preference ->
          {channel, %{opted_in: preference.opted_in, quiet_hours: preference.quiet_hours}}
      end
    end)
  end

  @doc "Whether the customer still wants this channel."
  @spec opted_in?(User.t(), atom()) :: boolean()
  def opted_in?(%User{} = user, channel), do: preferences(user)[channel].opted_in

  @doc "The quiet-hours window on a channel, or nil for any hour."
  @spec quiet_hours(User.t(), atom()) :: String.t() | nil
  def quiet_hours(%User{} = user, channel), do: preferences(user)[channel].quiet_hours

  @doc "Whether a message on this channel would be held back right now."
  @spec suppressed?(User.t(), atom()) :: boolean()
  def suppressed?(%User{} = user, channel) do
    not opted_in?(user, channel) or in_quiet_hours?(quiet_hours(user, channel))
  end

  @doc "Saves a customer's choices for both channels at once."
  @spec save_preferences(User.t(), map()) :: {:ok, :saved} | {:error, Ecto.Changeset.t()}
  def save_preferences(%User{} = user, params) do
    Enum.reduce_while(@channels, {:ok, :saved}, fn channel, _acc ->
      case upsert_preference(user, channel, params) do
        {:ok, _preference} -> {:cont, {:ok, :saved}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp upsert_preference(%User{} = user, channel, params) do
    attrs = %{
      user_id: user.id,
      channel: channel,
      opted_in: params["#{channel}_opted_in"] in [true, "true", "on", "1"],
      quiet_hours: blank_to_nil(params["#{channel}_quiet_hours"])
    }

    case Repo.get_by(NotificationPreference, user_id: user.id, channel: channel) do
      nil ->
        %NotificationPreference{} |> NotificationPreference.changeset(attrs) |> Repo.insert()

      preference ->
        preference |> NotificationPreference.changeset(attrs) |> Repo.update()
    end
  end

  # -- quiet hours -------------------------------------------------------

  @doc """
  Whether `time` (local) falls in a `"HH:MM-HH:MM"` window, wrapping midnight.

  A window whose start equals its end is treated as no quiet hours rather than
  twenty-four hours of silence.
  """
  @spec in_quiet_hours?(String.t() | nil, Time.t()) :: boolean()
  def in_quiet_hours?(range, time \\ local_time())

  def in_quiet_hours?(range, _time) when range in [nil, ""], do: false

  def in_quiet_hours?(range, %Time{} = time) do
    case parse_range(range) do
      {:ok, start_minutes, end_minutes} ->
        covers?(start_minutes, end_minutes, minute_of_day(time))

      :error ->
        false
    end
  end

  @doc "Seconds until the quiet window ends, so a snoozed message is not lost."
  @spec snooze_seconds(User.t(), atom()) :: pos_integer()
  def snooze_seconds(%User{} = user, channel) do
    case parse_range(quiet_hours(user, channel)) do
      {:ok, _start_minutes, end_minutes} ->
        remaining = rem(end_minutes - minute_of_day(local_time()) + 1_440, 1_440)
        max(remaining, 1) * 60

      :error ->
        60
    end
  end

  @doc "The current time in the customer's zone (Africa/Nairobi)."
  @spec local_time() :: Time.t()
  def local_time do
    DateTime.utc_now(:second)
    |> DateTime.add(@local_offset_seconds)
    |> DateTime.to_time()
  end

  defp covers?(start_minutes, end_minutes, _minute) when start_minutes == end_minutes, do: false

  defp covers?(start_minutes, end_minutes, minute) when start_minutes < end_minutes do
    minute >= start_minutes and minute < end_minutes
  end

  defp covers?(start_minutes, end_minutes, minute) do
    minute >= start_minutes or minute < end_minutes
  end

  defp parse_range(range) when is_binary(range) do
    with [start, finish] <- String.split(range, "-", parts: 2),
         {:ok, start_minutes} <- parse_hh_mm(start),
         {:ok, end_minutes} <- parse_hh_mm(finish) do
      {:ok, start_minutes, end_minutes}
    else
      _ -> :error
    end
  end

  defp parse_range(_range), do: :error

  defp parse_hh_mm(value) do
    with [hours, minutes] <- String.split(String.trim(value), ":", parts: 2),
         {hours, ""} <- Integer.parse(hours),
         {minutes, ""} <- Integer.parse(minutes),
         true <- hours in 0..23 and minutes in 0..59 do
      {:ok, hours * 60 + minutes}
    else
      _ -> :error
    end
  end

  defp minute_of_day(%Time{} = time), do: time.hour * 60 + time.minute

  # -- telling the customer ----------------------------------------------

  @doc "Queues the notification for an order event. Silently ignores an unknown event."
  @spec enqueue(Order.t(), atom()) :: {:ok, Oban.Job.t() | :unchanged} | {:error, term()}
  def enqueue(%Order{id: order_id}, event) when event in @events do
    %{order_id: order_id, event: to_string(event)} |> NotifyOrder.new() |> Oban.insert()
  catch
    :exit, reason ->
      Logger.warning("could not enqueue order notification: #{inspect(reason)}")
      {:ok, :unchanged}
  end

  def enqueue(%Order{}, _event), do: {:ok, :unchanged}

  @doc "The SMS template name and body for an order event."
  @spec sms(Order.t(), atom()) :: {String.t(), String.t()}
  def sms(%Order{} = order, event) do
    {"order_#{event}", sms_body(order, event)}
  end

  defp sms_body(order, :paid) do
    "Tangi: we have your #{amount(order)} for #{title(order)}. #{receipt_line(order)} " <>
      "We are placing your order."
  end

  defp sms_body(order, :completed) do
    "Tangi: your #{title(order)} order is complete. #{receipt_line(order)} " <>
      "Thank you — reopen the app to refill."
  end

  defp sms_body(order, :refunded) do
    "Tangi: #{amount(order)} is back in your wallet for #{title(order)}."
  end

  defp sms_body(order, :partial) do
    "Tangi: #{title(order)} was partly delivered; " <>
      "#{credit(order)} is back in your wallet."
  end

  @doc "Builds the receipt email for an order, carrying the M-Pesa code."
  @spec receipt_email(User.t(), Order.t()) :: Swoosh.Email.t()
  def receipt_email(%User{} = user, %Order{} = order) do
    ViewNinjas.Notifications.Receipt.email(user, order)
  end

  # -- helpers -----------------------------------------------------------

  defp receipt_line(order) do
    case order |> Payments.list_for_order() |> Enum.find_value(& &1.receipt) do
      nil -> "Paid from your wallet."
      code -> "Receipt #{code}."
    end
  end

  @doc "What the customer bought, for a message."
  @spec title(Order.t()) :: String.t()
  def title(%Order{lane: %{offer: %{title: title}}}) when is_binary(title), do: title
  def title(%Order{}), do: "your order"

  defp amount(%Order{retail_cents: cents}), do: Pricing.format_kes_cents(cents)

  defp credit(%Order{} = order) do
    case Orders.partial_cents(order) do
      nil -> "the unused part"
      cents -> Pricing.format_kes_cents(cents)
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
