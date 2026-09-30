defmodule ViewNinjas.Suppliers.V2 do
  @moduledoc """
  The single client every panel speaks through (scope.md §5): a `POST` form body
  with `action` plus `key`, JSON back.

  Errors are normalized to a few clear terms — `{:api_error, message}`,
  `{:http_error, status, body}`, `{:transport, reason}` and
  `{:invalid_response, body}` — so a wrong key surfaces as one sentence in the
  UI rather than a stack trace. HTTP goes through the app's shared Finch pool.
  """
  @behaviour ViewNinjas.Suppliers.Panel

  # Reads can take a moment; `add` is deliberately short, because a slow answer is
  # ambiguous and we would rather reconcile by hand than risk a second order (§5).
  @read_timeout 15_000
  @add_timeout 10_000

  @impl true
  def services(supplier) do
    with {:ok, body} <- request(supplier, "services") do
      case body do
        services when is_list(services) -> {:ok, Enum.map(services, &normalize_service/1)}
        %{"error" => message} -> {:error, {:api_error, message}}
        other -> {:error, {:invalid_response, other}}
      end
    end
  end

  @impl true
  def balance(supplier) do
    with {:ok, body} <- request(supplier, "balance") do
      case body do
        %{"error" => message} -> {:error, {:api_error, message}}
        %{"balance" => balance} -> normalize_balance(balance)
        other -> {:error, {:invalid_response, other}}
      end
    end
  end

  @impl true
  def add(supplier, service_external_id, link, quantity) do
    form = [service: service_external_id, link: link, quantity: quantity]

    with {:ok, body} <- request(supplier, "add", form, receive_timeout: @add_timeout) do
      case body do
        %{"order" => order_id} -> {:ok, to_string(order_id)}
        %{"error" => message} -> {:error, {:api_error, message}}
        other -> {:error, {:invalid_response, other}}
      end
    end
  end

  @impl true
  def status(supplier, supplier_order_ids) when is_list(supplier_order_ids) do
    with {:ok, body} <- request(supplier, "status", order: Enum.join(supplier_order_ids, ",")) do
      case body do
        %{"error" => message} -> {:error, {:api_error, message}}
        other -> {:ok, normalize_statuses(other)}
      end
    end
  end

  @impl true
  def refill(supplier, supplier_order_id) do
    with {:ok, body} <- request(supplier, "refill", order: supplier_order_id) do
      case body do
        %{"refill" => refill_id} -> {:ok, to_string(refill_id)}
        %{"error" => message} -> {:error, {:api_error, message}}
        other -> {:error, {:invalid_response, other}}
      end
    end
  end

  @impl true
  def refill_status(supplier, supplier_refill_id) do
    with {:ok, body} <- request(supplier, "refill_status", refill: supplier_refill_id) do
      case body do
        %{"status" => status} -> {:ok, to_string(status)}
        %{"error" => message} -> {:error, {:api_error, message}}
        other -> {:error, {:invalid_response, other}}
      end
    end
  end

  # -- internals ---------------------------------------------------------

  defp request(supplier, action, extra_form \\ [], opts \\ []) do
    req_options()
    |> Keyword.put(:url, supplier.base_url)
    |> Keyword.put(:form, Keyword.merge([key: supplier.api_key, action: action], extra_form))
    |> Keyword.put_new(:finch, ViewNinjas.Finch)
    |> Keyword.put_new(:retry, false)
    |> Keyword.put_new(:receive_timeout, Keyword.get(opts, :receive_timeout, @read_timeout))
    |> Req.post()
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_error, status, body}}

  defp handle_response({:error, reason}), do: {:error, {:transport, reason}}

  defp normalize_service(%{} = service) do
    %{
      external_id: to_string(service["service"]),
      name: service["name"],
      category: service["category"],
      type: service["type"],
      rate_micros: parse_micros(service["rate"]),
      min: parse_integer(service["min"]),
      max: parse_integer(service["max"]),
      refill: truthy?(service["refill"]),
      cancel: truthy?(service["cancel"])
    }
  end

  defp normalize_balance(balance) do
    case parse_micros(balance) do
      nil -> {:error, {:invalid_response, balance}}
      micros -> {:ok, micros}
    end
  end

  # Panels disagree on the shape: `{"orders": {id: {...}}}`, `{id: {...}}`, a list
  # of entries, or a single flat object. All of them collapse to one list.
  defp normalize_statuses(body) when is_map(body) do
    cond do
      is_map(body["orders"]) -> normalize_statuses(body["orders"])
      Map.has_key?(body, "status") -> [normalize_status(nil, body)]
      true -> for {id, entry} <- body, is_map(entry), do: normalize_status(id, entry)
    end
  end

  defp normalize_statuses(body) when is_list(body) do
    for entry <- body, is_map(entry), do: normalize_status(entry["order"], entry)
  end

  defp normalize_statuses(_body), do: []

  defp normalize_status(id, entry) do
    %{
      external_order_id: to_string(id || entry["order"]),
      status: entry["status"],
      start_count: parse_integer(entry["start_count"]),
      remains: parse_integer(entry["remains"]),
      charge_usd_micros: parse_micros(entry["charge"]),
      currency: entry["currency"]
    }
  end

  # "0.90" -> 900_000 micros of a dollar. No floats in the database.
  defp parse_micros(value) when is_number(value), do: round(value * 1_000_000)

  defp parse_micros(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        decimal
        |> Decimal.mult(1_000_000)
        |> Decimal.round(0, :down)
        |> Decimal.to_integer()

      _ ->
        nil
    end
  end

  defp parse_micros(_), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp req_options, do: Application.get_env(:viewninjas, :suppliers, [])[:req_options] || []
end
