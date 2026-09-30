defmodule ViewNinjasWeb.SmsCallbackController do
  @moduledoc """
  TextSMS delivery reports (build-plan.md M2).

  The body is a hint, not the truth: we match the report's message id against
  the reference we stored and update the status. Unknown ids are acknowledged
  and ignored, so the provider does not retry forever.
  """
  use ViewNinjasWeb, :controller

  alias ViewNinjas.Sms

  @ref_keys ~w(messageid messageId message_id id)
  @status_keys ~w(status delivery_status response-description response_description)

  def text_sms(conn, params) do
    with ref when is_binary(ref) <- first(params, @ref_keys),
         status when not is_nil(status) <- normalize(first(params, @status_keys)) do
      _ = Sms.record_delivery(ref, status)
      send_resp(conn, 200, "ok")
    else
      _ -> send_resp(conn, 200, "ignored")
    end
  end

  defp first(params, keys), do: Enum.find_value(keys, &params[&1])

  defp normalize(value) when is_binary(value) do
    case String.downcase(value) do
      v when v in ["delivered", "success", "successful"] -> :delivered
      "sent" -> :sent
      v when v in ["failed", "rejected", "undelivered", "expired", "invalid"] -> :failed
      _ -> nil
    end
  end

  defp normalize(_), do: nil
end
