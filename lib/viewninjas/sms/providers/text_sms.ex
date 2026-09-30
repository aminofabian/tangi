defmodule ViewNinjas.Sms.Providers.TextSms do
  @moduledoc """
  TextSMS (Kenya) bulk SMS, over Req.

  Credentials and the endpoint come from config/environment
  (`TEXTSMS_API_KEY`, `TEXTSMS_PARTNER_ID`, optional `TEXTSMS_SHORTCODE`).
  Nothing is committed, and a missing key fails the call with a clear
  `:sms_not_configured` error rather than silently doing nothing.

  The endpoint is configurable (`:endpoint`) because TextSMS runs more than one
  API host; the default is the common one.
  """
  @behaviour ViewNinjas.Sms.Provider

  alias ViewNinjas.Settings

  @default_endpoint "https://sms.textsms.co.ke/api/services/sendsms/"

  @impl true
  def send_sms(to, body) do
    with {:ok, config} <- config() do
      config
      |> build_request(to, body)
      |> Req.post()
      |> handle_response()
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"responses" => [response | _]}}}) do
    case response do
      %{"response-code" => 200} -> {:ok, normalize(response)}
      %{"response-description" => description} -> {:error, {:provider_rejected, description}}
      other -> {:error, {:unexpected_body, other}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:error, {:unexpected_body, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:unexpected_response, status, body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}

  # TextSMS does not report a per-message cost, so the daily cap falls back to
  # the configured estimate until the settlement is reconciled (M10).
  defp normalize(response) do
    %{provider_ref: response["messageid"], status: :sent, cost_micros: nil}
  end

  defp config do
    with api_key when is_binary(api_key) <- Settings.textsms_api_key(),
         partner_id when is_binary(partner_id) <- Settings.textsms_partner_id() do
      {:ok,
       %{
         api_key: api_key,
         partner_id: partner_id,
         shortcode: Settings.textsms_shortcode(),
         endpoint: Settings.textsms_endpoint() || @default_endpoint,
         req: req_options()
       }}
    else
      _ -> {:error, :sms_not_configured}
    end
  end

  defp req_options do
    :viewninjas |> Application.get_env(:sms, []) |> Keyword.get(:req_options, [])
  end

  defp build_request(config, to, body) do
    payload =
      %{
        "apikey" => config.api_key,
        "partnerID" => config.partner_id,
        "mobile" => to,
        "message" => body
      }
      |> maybe_put("shortcode", config.shortcode)

    Req.new(url: config.endpoint, json: payload) |> Req.merge(config.req)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
