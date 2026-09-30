defmodule ViewNinjas.Workers.InsightWorkersTest do
  @moduledoc """
  The M10 jobs (build-plan.md M10): the daily rollup, the anomaly pass and the
  Sunday digest.
  """

  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Ecto.Query
  import Swoosh.TestAssertions
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.{Alerts, Traffic}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo
  alias ViewNinjas.Workers.{CheckAnomalies, RollupDaily, WeeklyDigest}

  test "RollupDaily writes yesterday's row" do
    assert :ok = perform_job(RollupDaily, %{})

    yesterday = Date.add(Date.utc_today(), -1)
    assert [%{day: ^yesterday}] = Traffic.daily(yesterday, yesterday)
  end

  test "CheckAnomalies raises what it finds" do
    Alerts.subscribe()
    Enum.each(1..5, fn _ -> failed_payment("customer_timeout") end)

    assert :ok = perform_job(CheckAnomalies, %{})

    assert_receive {:alert, %{kind: :failure_spike}}
  end

  test "WeeklyDigest sends to a super-admin and is quiet without one" do
    assert :ok = perform_job(WeeklyDigest, %{})
    refute_email_sent()

    super_admin_fixture(%{email: "boss@viewninjas.test"})
    assert :ok = perform_job(WeeklyDigest, %{})

    assert_email_sent(fn email -> email.subject =~ "ViewNinjas week" end)
  end

  defp failed_payment(failure_kind) do
    socket = System.unique_integer([:positive])

    {:ok, payment} =
      Repo.insert(%Payment{
        user_id: user_fixture().id,
        purpose: :order,
        amount_cents: 1_000,
        idempotency_key: "anomaly-#{socket}",
        status: :failed,
        failure_kind: failure_kind
      })

    Repo.update_all(
      from(p in Payment, where: p.id == ^payment.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -3_600)]
    )
  end
end
