defmodule ViewNinjas.Workers.FetchFxRate do
  @moduledoc """
  Records the day's USD→KES rate from a configured source (build-plan.md M5).

  The source is configuration, not code: with no `FX_SOURCE_URL` the job is a
  no-op, so the app prices from the §7 default or the last recorded rate until a
  provider is named. The request goes through the shared Finch pool, and outbound
  calls only ever happen in a worker, never on a page (scope.md §13).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias ViewNinjas.Pricing
  alias ViewNinjas.Settings

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Settings.fx_source_url() do
      nil ->
        Logger.info("fx: no FX_SOURCE_URL configured; skipping the daily rate")
        :ok

      url ->
        fetch(url)
    end
  end

  defp fetch(url) do
    url
    |> request_options()
    |> Req.get()
    |> handle_response()
  end

  defp request_options(url) do
    req_options()
    |> Keyword.put(:url, url)
    |> Keyword.put_new(:finch, ViewNinjas.Finch)
    |> Keyword.put_new(:retry, false)
    |> Keyword.put_new(:receive_timeout, 15_000)
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: record(body)

  defp handle_response({:ok, %{status: status}}),
    do: {:error, "fx source answered HTTP #{status}"}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp record(body) do
    case rate_ppm(body) do
      {:ok, ppm} ->
        {:ok, _rate} = Pricing.record_fx_rate(%{rate_ppm: ppm, source: "daily"}, nil)
        :ok

      :error ->
        Logger.warning("fx: source answered something we could not read")
        :ok
    end
  end

  # The rate is the number at the configured path, e.g. "rates.KES" -> 129.40.
  defp rate_ppm(body) do
    case get_in(body, path()) do
      nil -> :error
      value -> to_ppm(value)
    end
  end

  defp to_ppm(value) do
    case Decimal.parse(to_string(value)) do
      {decimal, ""} ->
        {:ok,
         decimal |> Decimal.mult(1_000_000) |> Decimal.round(0, :half_up) |> Decimal.to_integer()}

      _ ->
        :error
    end
  end

  defp path do
    Settings.fx_source_path()
    |> String.split(".", trim: true)
  end

  defp req_options do
    :viewninjas |> Application.get_env(:pricing, []) |> Keyword.get(:fx_req_options, [])
  end
end
