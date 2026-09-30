defmodule ViewNinjas.Payments.Malipo do
  @moduledoc """
  The Malipo Connect client (scope.md §8, `docs/malipo-connect.md`).

  `create/1` pushes an M-Pesa prompt; `get/1` reads a payment's final state and
  is the **source of truth**. It holds no state, and the key comes from config,
  never the module — so nothing in the repo or a log carries a secret.

  Errors normalize to a few clear terms: `{:error, :not_configured}`,
  `{:error, {:malipo, code, message, status}}` (the code stays a string, so a
  bad payload cannot exhaust the atom table) and `{:error, {:transport, reason}}`.
  HTTP goes through the app's shared Finch pool, with Req as the client.
  """

  @behaviour ViewNinjas.Payments.Provider

  alias ViewNinjas.Settings

  @receive_timeout 15_000

  @impl true
  def create(attrs) do
    body =
      %{
        amount: attrs.amount,
        customer_phone: attrs.customer_phone,
        idempotency_key: attrs.idempotency_key
      }
      |> put_optional(:reference, attrs[:reference])
      |> put_optional(:callback_url, attrs[:callback_url])
      |> put_optional(:currency, attrs[:currency])

    request(:post, create_url(), Jason.encode!(body))
  end

  @impl true
  def get(id), do: request(:get, check_url(id), nil)

  @doc "A short sentence for a normalized error, safe to show a customer."
  @spec error_message(term()) :: String.t()
  def error_message(:not_configured), do: "Payments are not configured yet."

  def error_message({:malipo, "destination_inactive", _message, _status}),
    do: "This shop has no payment destination yet."

  def error_message({:malipo, "invalid_phone", _message, _status}),
    do: "That phone number was not accepted."

  def error_message({:malipo, "unauthorized", _message, _status}),
    do: "The payment key was rejected."

  def error_message({:malipo, _code, message, _status}) when is_binary(message), do: message

  def error_message({:malipo, _code, _message, status}),
    do: "The payment rail answered #{status}."

  def error_message({:transport, _reason}), do: "Could not reach the payment rail."
  def error_message(_other), do: "Payments are unavailable just now."

  defp request(method, url, body) do
    with {:ok, key} <- credential() do
      options =
        req_options()
        |> Keyword.put(:method, method)
        |> Keyword.put(:url, url)
        |> Keyword.put(:headers, [
          {"authorization", "Bearer " <> key},
          {"content-type", "application/json"}
        ])
        |> Keyword.put(:body, body)
        |> Keyword.put_new(:finch, ViewNinjas.Finch)
        |> Keyword.put_new(:retry, false)
        |> Keyword.put_new(:receive_timeout, @receive_timeout)

      case Req.request(options) do
        {:ok, %{status: status, body: raw}} when status in [200, 201] -> to_payment(raw)
        {:ok, %{status: status, body: raw}} -> {:error, to_error(status, raw)}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  defp to_payment(raw) do
    with {:ok, json} when is_map(json) <- decode(raw),
         {:ok, status} <- to_status(json["status"]) do
      {:ok,
       %{
         id: json["id"],
         status: status,
         amount: json["amount"],
         currency: json["currency"],
         receipt: json["receipt"],
         failure_kind: json["failure_kind"],
         failure_message: json["failure_message"],
         customer_phone: json["customer_phone"]
       }}
    else
      _ -> {:error, {:invalid_response, raw}}
    end
  end

  defp decode(raw) when is_map(raw), do: {:ok, raw}
  defp decode(raw) when is_binary(raw), do: Jason.decode(raw)
  defp decode(_raw), do: :error

  defp to_status("pending"), do: {:ok, :pending}
  defp to_status("settled"), do: {:ok, :settled}
  defp to_status("failed"), do: {:ok, :failed}
  defp to_status(_other), do: :error

  # The code stays a string so a bad payload cannot exhaust the atom table.
  defp to_error(status, raw) do
    case decode(raw) do
      {:ok, %{"error" => code} = json} -> {:malipo, code, json["message"], status}
      _ -> {:http_error, status}
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  # The secret key wins when Connect issued an sk_live_… key. Otherwise the
  # client id (pk_live_…) is the bearer, which is what Connect shows as Client ID.
  defp credential do
    case blank_to_nil(Settings.malipo_secret_key()) || blank_to_nil(Settings.malipo_client_id()) do
      key when is_binary(key) -> {:ok, key}
      _ -> {:error, :not_configured}
    end
  end

  defp create_url, do: absolute(Settings.malipo_create_path())

  defp check_url(id) do
    Settings.malipo_check_path()
    |> String.replace("{id}", URI.encode(to_string(id)))
    |> absolute()
  end

  defp absolute(path) do
    path = path |> to_string() |> String.trim()

    if String.starts_with?(path, "https://") or String.starts_with?(path, "http://") do
      path
    else
      base = Settings.malipo_base_url() |> to_string() |> String.trim_trailing("/")
      relative = if String.starts_with?(path, "/"), do: path, else: "/" <> path
      base <> relative
    end
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp req_options do
    :viewninjas |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
  end
end
