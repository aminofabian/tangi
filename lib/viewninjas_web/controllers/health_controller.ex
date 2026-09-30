defmodule ViewNinjasWeb.HealthController do
  @moduledoc """
  Liveness and readiness probe.

  Answers `200` only when the app is up and the database answers a trivial
  query, and `503` otherwise so the platform can pull an unhealthy node out
  of rotation. It deliberately runs without a session, CSRF protection, or
  HTML rendering.
  """
  use ViewNinjasWeb, :controller

  def show(conn, _params) do
    if database_up?() do
      json(conn, %{status: "ok"})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable"})
    end
  end

  defp database_up? do
    match?(
      {:ok, _},
      Ecto.Adapters.SQL.query(ViewNinjas.Repo, "SELECT 1", [], timeout: 2_000)
    )
  rescue
    # A down or unreachable database must not crash the probe.
    _ -> false
  end
end
