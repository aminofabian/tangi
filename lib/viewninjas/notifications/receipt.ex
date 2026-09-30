defmodule ViewNinjas.Notifications.Receipt do
  @moduledoc """
  The email receipt (scope.md §11; build-plan.md M11): what was bought, what it
  cost, and the M-Pesa code that proves it. Sent once, when an order is paid.
  """

  import Swoosh.Email

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Notifications
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments
  alias ViewNinjas.Pricing
  alias ViewNinjas.Settings

  @doc "The receipt email for one order, addressed to the customer."
  @spec email(User.t(), Order.t()) :: Swoosh.Email.t()
  def email(%User{} = user, %Order{} = order) do
    new()
    |> to(user.email)
    |> from(sender())
    |> subject("Your ViewNinjas receipt")
    |> text_body(body(order))
  end

  defp body(order) do
    [
      "Thank you for your order.",
      "",
      "What:     #{Notifications.title(order)}",
      "How many: #{order.quantity}",
      "Link:     #{order.link}",
      "Paid:     #{Pricing.format_kes_cents(order.retail_cents)}",
      "M-Pesa:   #{receipt(order)}",
      "",
      "We will text you when it is placed and when it is done."
    ]
    |> Enum.join("\n")
  end

  defp receipt(order) do
    case order |> Payments.list_for_order() |> Enum.find_value(& &1.receipt) do
      nil -> "Paid from your wallet."
      code -> code
    end
  end

  defp sender, do: Settings.mailer_from()
end
