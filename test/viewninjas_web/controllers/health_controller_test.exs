defmodule ViewNinjasWeb.HealthControllerTest do
  use ViewNinjasWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns ok when the database answers", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end
end
