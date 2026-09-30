defmodule ViewNinjasWeb.MalipoCallbackController do
  @moduledoc """
  Malipo's payment callback (scope.md §8, `docs/malipo-connect.md` §9).

  Answers `2xx` fast and does the real work in Oban, because Malipo retries until
  it gets a quick `2xx`. The body is a **hint**: it only tells us which payment to
  confirm. The confirming `GET` in `ConfirmPayment` is what may move money, so a
  replayed or forged POST cannot settle anything on its own — which is also why
  deduping on the event id is unnecessary: a second callback only asks for the
  same idempotent confirmation.

  The signature check is optional. When `MALIPO_WEBHOOK_SECRET` is set it must
  match the HMAC of the raw body; when it is not, the confirming GET still holds.
  """

  use ViewNinjasWeb, :controller

  require Logger

  alias ViewNinjas.Payments
  alias ViewNinjas.Settings
  alias ViewNinjas.Workers.ConfirmPayment
  alias ViewNinjasWeb.BodyReader

  def create(conn, params) do
    if verify(conn) do
      handle(conn, params)
    else
      send_resp(conn, 400, "bad signature")
    end
  end

  defp handle(conn, params) do
    case params["data"]["id"] do
      malipo_id when is_binary(malipo_id) -> enqueue(conn, malipo_id)
      _ -> send_resp(conn, 400, "ignored")
    end
  rescue
    # A malformed body is not worth a retry loop; ack and move on.
    _error -> send_resp(conn, 202, "")
  end

  defp enqueue(conn, malipo_id) do
    case Payments.get_payment_by_malipo_id(malipo_id) do
      nil ->
        # Not one of ours: acknowledge so Malipo does not retry forever.
        send_resp(conn, 202, "")

      payment ->
        _ = ConfirmPayment.enqueue(payment.id)
        send_resp(conn, 200, "")
    end
  end

  defp verify(conn) do
    case webhook_secret() do
      nil -> true
      secret -> signature_valid?(conn, secret)
    end
  end

  defp signature_valid?(conn, secret) do
    case get_req_header(conn, "x-malipo-signature") do
      [header | _] ->
        expected = :crypto.mac(:hmac, :sha256, secret, BodyReader.raw_body(conn))

        case decode_signature(header) do
          {:ok, received} -> Plug.Crypto.secure_compare(expected, received)
          :error -> false
        end

      [] ->
        false
    end
  end

  defp decode_signature(header) do
    header
    |> String.replace_prefix("sha256=", "")
    |> Base.decode16(case: :mixed)
  end

  defp webhook_secret do
    case Settings.malipo_webhook_secret() do
      secret when is_binary(secret) and secret != "" -> secret
      _ -> nil
    end
  end
end
