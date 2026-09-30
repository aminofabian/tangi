defmodule ViewNinjas.Workers.FetchFxRateTest do
  # Mutates global pricing config (the Req test plug), so keep this serial.
  use ViewNinjas.DataCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ExUnit.CaptureLog
  import ViewNinjas.PricingFixtures

  alias ViewNinjas.Pricing
  alias ViewNinjas.Workers.FetchFxRate

  setup do
    previous = Application.get_env(:viewninjas, :pricing, [])

    on_exit(fn ->
      Application.put_env(:viewninjas, :pricing, previous)
    end)

    :ok
  end

  defp configure(options) do
    Application.put_env(:viewninjas, :pricing, Keyword.merge(options, fx_req_options: []))
  end

  test "with no source configured it records nothing" do
    configure(fx_source_url: nil)

    assert :ok = perform_job(FetchFxRate, %{})
    assert Pricing.current_fx() == nil
  end

  test "it records the day's rate from the configured source" do
    configure(fx_source_url: "https://fx.test/latest", fx_source_path: "rates.KES")

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"base" => "USD", "rates" => %{"KES" => 129.4}})
    end)

    Application.put_env(
      :viewninjas,
      :pricing,
      fx_source_url: "https://fx.test/latest",
      fx_source_path: "rates.KES",
      fx_req_options: [plug: {Req.Test, __MODULE__}]
    )

    assert :ok = perform_job(FetchFxRate, %{})

    rate = Pricing.current_fx()
    assert rate.source == "daily"
    assert rate.rate_ppm == 129_400_000
    assert rate.actor_id == nil
  end

  test "an unreadable body is logged, not recorded, and not retried" do
    Application.put_env(
      :viewninjas,
      :pricing,
      fx_source_url: "https://fx.test/latest",
      fx_source_path: "rates.KES",
      fx_req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"unexpected" => true}) end)

    assert capture_log(fn -> assert :ok = perform_job(FetchFxRate, %{}) end) =~
             "something we could not read"

    assert Pricing.current_fx() == nil
  end

  test "a 5xx is retried" do
    Application.put_env(
      :viewninjas,
      :pricing,
      fx_source_url: "https://fx.test/latest",
      fx_req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 502, "bad gateway") end)

    assert {:error, _reason} = perform_job(FetchFxRate, %{})
    assert Pricing.current_fx() == nil
  end

  test "the fixture path just records a rate" do
    rate = fx_rate_fixture(%{rate_ppm: 129_400_000, source: "fixture"})

    assert rate.source == "fixture"
    assert Pricing.fx_ppm() == 129_400_000
  end
end
