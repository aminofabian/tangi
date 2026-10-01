defmodule ViewNinjas.Airtime.Instalipa do
  @moduledoc """
  The Instalipa airtime client (scope: `docs/instalipa-airtime.md` §3–§4).

  `send_airtime/1` asks Instalipa to put airtime on a number; `status/1` reads a
  transaction's final state and is the **source of truth**. It holds no state, and the
  consumer key and secret come from `Settings` (encrypted at rest), never the module —
  so nothing in the repo or a log carries a secret.

  Unlike the payment rail, this one is not authenticated by a fixed bearer: it needs a
  token minted from the credentials, which `ViewNinjas.Airtime.Instalipa.Token` caches
  and refreshes. A `401` on a call made with a cached token mints a new one and retries
  **once** — a stale token is expected, a rejected credential is not.

  Errors normalize to a few clear terms: `:not_configured`, `:duplicate`,
  `{:instalipa, code, message, status}` (the code stays a string, so a bad payload
  cannot exhaust the atom table) and `{:transport, reason}`. HTTP goes through the app's
  shared Finch pool, with Req as the client.
  """

  @behaviour ViewNinjas.Airtime.Provider

  require Logger

  alias ViewNinjas.Airtime.Instalipa.Token
  alias ViewNinjas.Settings

  @receive_timeout 15_000

  @impl true
  def send_airtime(attrs) do
    body =
      %{phone_number: attrs.phone, amount: attrs.amount}
      |> put_optional(:reference, attrs[:reference])
      |> Jason.encode!()

    with_token(fn token ->
      request(:post, airtime_url(), body, token, idempotency_key: attrs[:idempotency_key])
    end)
    |> transact()
  end

  @impl true
  def status(transaction_id) do
    with_token(fn token -> request(:get, status_url(transaction_id), nil, token, []) end)
    |> transact()
  end

  @doc """
  Mints a token from the consumer credentials. Called by the token cache, not by
  callers — the cache is what keeps it to one fetch an hour.
  """
  @spec request_token() :: {:ok, String.t(), pos_integer()} | {:error, term()}
  def request_token do
    with {:ok, {key, secret}} <- credentials() do
      basic = "Basic " <> Base.encode64(key <> ":" <> secret)

      case raw_request(:post, token_url(), nil, [
             {"authorization", basic},
             {"content-type", "application/json"}
           ]) do
        {:ok, %{status: status, body: raw}} when status in [200, 201] -> to_token(raw)
        {:ok, %{status: status, body: raw}} -> {:error, to_error(status, raw)}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc "Whether the consumer key and secret are both saved."
  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _}, credentials())

  @doc "A short sentence for a normalized error, safe to show a customer."
  @spec error_message(term()) :: String.t()
  def error_message(:not_configured), do: "Airtime is not configured yet."

  def error_message(:duplicate),
    do: "That looks like a duplicate request — check before trying again."

  def error_message(:unauthorized), do: "The airtime rail rejected its credentials."

  def error_message({:instalipa, _code, message, _status}) when is_binary(message), do: message

  def error_message({:instalipa, _code, _message, status}),
    do: "The airtime rail answered #{status}."

  def error_message({:transport, _reason}), do: "Could not reach the airtime rail."
  def error_message(_other), do: "Airtime is unavailable just now."

  # -- the two-step call -------------------------------------------------

  # Get a token, make the call, and on a 401 mint a fresh token and try once more.
  # A second 401 is a rejected credential, not a stale token, and is left to surface.
  defp with_token(fun) do
    with {:ok, token} <- Token.fetch() do
      fun.(token) |> retry_on_unauthorized(fun)
    end
  end

  defp retry_on_unauthorized({:ok, %{status: 401}}, fun) do
    with {:ok, fresh} <- Token.refresh(), do: fun.(fresh)
  end

  defp retry_on_unauthorized(other, _fun), do: other

  defp transact(result) do
    case result do
      {:ok, %{status: status, body: raw}} when status in [200, 201] -> to_transaction(raw)
      {:ok, %{status: status, body: raw}} -> {:error, to_error(status, raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_transaction(raw) do
    with {:ok, json} when is_map(json) <- decode(raw),
         {:ok, status} <- to_status(json["status"]) do
      if duplicate?(json) do
        {:error, :duplicate}
      else
        {:ok,
         %{
           id: json["transaction_id"],
           status: status,
           phone: json["phone_number"],
           amount: json["amount"],
           discount: json["discount"],
           balance: json["balance"],
           reference: json["reference"],
           receipt: json["receipt"]
         }}
      end
    else
      _ -> {:error, {:invalid_response, raw}}
    end
  end

  # The rail answers a repeat within its window with a Failed body and this detail;
  # it is our own retry landing twice, not a top-up that failed (scope §3.5).
  defp duplicate?(%{"details" => "Duplicate request"}), do: true
  defp duplicate?(_json), do: false

  # The rail's word for a transaction, as an atom we control; an unknown word is an
  # unreadable response, never a new atom.
  defp to_status("Submitted"), do: {:ok, :submitted}
  defp to_status("Pending"), do: {:ok, :pending}
  defp to_status("Success"), do: {:ok, :success}
  defp to_status("Failed"), do: {:ok, :failed}
  defp to_status(_other), do: :error

  defp to_token(raw) do
    with {:ok, json} when is_map(json) <- decode(raw),
         token when is_binary(token) and token != "" <- json["access_token"] do
      {:ok, token, expires_in(json)}
    else
      _ -> {:error, {:invalid_response, raw}}
    end
  end

  defp expires_in(%{"expires_in" => value}) when is_number(value), do: trunc(value)

  defp expires_in(%{"expires_in" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> 3_600
    end
  end

  defp expires_in(_json), do: 3_600

  # -- HTTP --------------------------------------------------------------

  defp request(method, url, body, token, opts) do
    headers =
      [{"authorization", "Bearer " <> token}, {"content-type", "application/json"}] ++
        idempotency_headers(opts)

    raw_request(method, url, body, headers)
  end

  defp idempotency_headers(opts) do
    case Keyword.get(opts, :idempotency_key) do
      nil -> []
      key -> [{"idempotency-key", to_string(key)}]
    end
  end

  defp raw_request(method, url, body, headers) do
    options =
      req_options()
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, url)
      |> Keyword.put(:headers, headers)
      |> Keyword.put(:body, body)
      |> Keyword.put_new(:finch, ViewNinjas.Finch)
      |> Keyword.put_new(:retry, false)
      # Take the body raw and decode it here, so a malformed payload is an
      # `:invalid_response` we control rather than a Req decode error.
      |> Keyword.put_new(:decode_body, false)
      |> Keyword.put_new(:receive_timeout, @receive_timeout)

    case Req.request(options) do
      {:ok, %{status: status} = response} ->
        Logger.info("instalipa #{method} #{log_url(url)} status=#{status}")
        {:ok, response}

      {:error, reason} ->
        Logger.warning("instalipa #{method} #{log_url(url)} transport")
        {:error, {:transport, reason}}
    end
  end

  # The code stays a string so a bad payload cannot exhaust the atom table.
  defp to_error(status, raw) do
    case decode(raw) do
      {:ok, %{"error" => code} = json} -> {:instalipa, code, error_detail(json), status}
      {:ok, json} when is_map(json) -> {:instalipa, nil, error_detail(json), status}
      _ -> {:http_error, status}
    end
  end

  defp error_detail(%{"message" => message}) when is_binary(message), do: message
  defp error_detail(%{"details" => details}) when is_binary(details), do: details
  defp error_detail(%{"error" => error}) when is_binary(error), do: error
  defp error_detail(_json), do: nil

  defp decode(raw) when is_map(raw), do: {:ok, raw}
  defp decode(raw) when is_binary(raw), do: Jason.decode(raw)
  defp decode(_raw), do: :error

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp credentials do
    with key when is_binary(key) and key != "" <- present(Settings.instalipa_consumer_key()),
         secret when is_binary(secret) and secret != "" <-
           present(Settings.instalipa_consumer_secret()) do
      {:ok, {key, secret}}
    else
      _ -> {:error, :not_configured}
    end
  end

  defp present(value) when is_binary(value), do: String.trim(value)
  defp present(_value), do: nil

  defp token_url, do: absolute(Settings.instalipa_token_path())
  defp airtime_url, do: absolute(Settings.instalipa_airtime_path())

  defp status_url(transaction_id) do
    Settings.instalipa_status_path()
    |> String.replace("{id}", URI.encode(to_string(transaction_id)))
    |> absolute()
  end

  defp absolute(path) do
    path = path |> to_string() |> String.trim()

    if String.starts_with?(path, "https://") or String.starts_with?(path, "http://") do
      path
    else
      base = Settings.instalipa_base_url() |> to_string() |> String.trim_trailing("/")
      relative = if String.starts_with?(path, "/"), do: path, else: "/" <> path
      base <> relative
    end
  end

  # Host and path only. Query and userinfo stay out of the log.
  defp log_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, path: path} = uri
      when is_binary(scheme) and is_binary(host) ->
        path = path || "/"

        if uri.port in [nil, URI.default_port(scheme)] do
          "#{scheme}://#{host}#{path}"
        else
          "#{scheme}://#{host}:#{uri.port}#{path}"
        end

      _ ->
        "unparsed"
    end
  end

  defp req_options do
    :viewninjas |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
  end
end
