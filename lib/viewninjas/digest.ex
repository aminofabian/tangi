defmodule ViewNinjas.Digest do
  @moduledoc """
  The Sunday message (scope.md §11; build-plan.md M10).

  One email to every super-admin with the week's profit, orders, new customers,
  conversion, the best lane and anything that alerted — the report you read even
  when you do not open the back office. Sent by `WeeklyDigest`; nothing is stored.
  """

  import Swoosh.Email

  alias ViewNinjas.Accounts
  alias ViewNinjas.Analysis
  alias ViewNinjas.Mailer
  alias ViewNinjas.Pricing
  alias ViewNinjas.Progress
  alias ViewNinjas.Settings

  @doc "The addresses the digest goes to: every super-admin with an email."
  @spec recipients() :: [String.t()]
  def recipients, do: Accounts.list_super_admin_emails()

  @doc "Composes and sends the week's digest; returns how many emails went out."
  @spec deliver(Date.t()) :: non_neg_integer()
  def deliver(at \\ Date.utc_today()) do
    digest = Analysis.digest(at)
    recipients = recipients()
    Enum.each(recipients, &Mailer.deliver(email(digest, &1)))
    length(recipients)
  end

  @doc "Builds the digest email for one recipient."
  @spec email(map(), String.t()) :: Swoosh.Email.t()
  def email(digest, to) do
    new()
    |> to(to)
    |> from(sender())
    |> subject(subject(digest))
    |> text_body(body(digest))
  end

  @doc "The digest as plain text, for the screen and the email alike."
  @spec body(map()) :: String.t()
  def body(digest) do
    p = digest.profit

    [
      "ViewNinjas — week to #{Date.to_iso8601(p.to_date)}",
      "",
      "Net profit:   #{money(p.net_cents)}",
      "Revenue:      #{money(p.revenue_cents)}",
      "Cost of goods:#{money(p.cogs_cents)}",
      "Other costs:  #{money(p.fees_cents + p.sms_cents + p.other_cents)}",
      "Orders:       #{digest.orders}",
      "New customers:#{digest.new_customers}",
      "Conversion:   #{percent(digest.conversion)}",
      "Best lane:    #{best_lane(digest.best_lane)}",
      "",
      anomalies(digest.anomalies)
    ]
    |> Enum.join("\n")
  end

  defp subject(digest) do
    "ViewNinjas week: #{money(digest.profit.net_cents)} net, #{digest.orders} orders"
  end

  defp anomalies([]), do: "Nothing alerted."

  defp anomalies(anomalies) do
    "Alerts:\n" <> Enum.map_join(anomalies, "\n", fn {_kind, message} -> "  • #{message}" end)
  end

  defp best_lane(nil), do: "no charged orders yet"

  defp best_lane(%{lane_id: lane_id, profit_cents: profit}) do
    "lane ##{lane_id}, #{money(profit)}"
  end

  defp percent(nil), do: "—"
  defp percent(fraction), do: Progress.format(:margin, round(fraction * 10_000))

  defp money(nil), do: "—"
  defp money(cents), do: Pricing.format_kes_cents(cents)

  defp sender, do: Settings.mailer_from()
end
