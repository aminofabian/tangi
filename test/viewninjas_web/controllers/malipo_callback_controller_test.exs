defmodule ViewNinjasWeb.MalipoCallbackControllerTest do
  @moduledoc """
  The Malipo callback (build-plan.md M7, scope.md §8). Answers fast, and treats
  the body as a hint: it only asks for a confirmation, never settles anything
  itself.
  """

  # Sets the global webhook secret, so keep this serial.
  use ViewNinjasWeb.ConnCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Payments
  alias ViewNinjas.Workers.ConfirmPayment

  @path "/webhooks/malipo"

  setup do
    previous = Application.get_env(:viewninjas, :malipo_webhook_secret)
    on_exit(fn -> Application.put_env(:viewninjas, :malipo_webhook_secret, previous) end)
    :ok
  end

  test "a callback enqueues a confirmation and answers 200", %{conn: conn} do
    payment = payment_fixture()
    {:ok, sent} = Payments.mark_pending(payment, "malipo-abc")

    conn = post(conn, @path, %{"event" => "payment.settled", "data" => %{"id" => "malipo-abc"}})

    assert response(conn, 200)
    assert [%{args: %{"payment_id" => id}}] = all_enqueued(worker: ConfirmPayment)
    assert id == sent.id
  end

  test "a callback for an id we do not know is acknowledged, not retried", %{conn: conn} do
    conn = post(conn, @path, %{"data" => %{"id" => "malipo-unknown"}})

    assert response(conn, 202)
    assert all_enqueued(worker: ConfirmPayment) == []
  end

  test "a malformed body is acknowledged so it does not loop", %{conn: conn} do
    conn = post(conn, @path, %{"event" => "payment.settled"})

    assert response(conn, 400)
  end

  test "the callback never settles anything on its own", %{conn: conn} do
    order = order_fixture()
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-abc")

    post(conn, @path, %{"event" => "payment.settled", "data" => %{"id" => "malipo-abc"}})

    # Only the confirming GET may move money, so nothing has settled yet.
    assert Payments.get_payment!(sent.id).status == :pending
    assert ViewNinjas.Orders.get_order!(order.id).state == :awaiting_payment
  end

  describe "with a signing secret configured" do
    setup do
      Application.put_env(:viewninjas, :malipo_webhook_secret, "whsec_test")
      :ok
    end

    test "a good signature is accepted", %{conn: conn} do
      payment = payment_fixture()
      {:ok, _sent} = Payments.mark_pending(payment, "malipo-sig")

      body = Jason.encode!(%{"event" => "payment.settled", "data" => %{"id" => "malipo-sig"}})
      signature = sign(body, "whsec_test")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-malipo-signature", signature)
        |> post(@path, body)

      assert response(conn, 200)
      assert all_enqueued(worker: ConfirmPayment) != []
    end

    test "a bad signature is rejected", %{conn: conn} do
      body = Jason.encode!(%{"event" => "payment.settled", "data" => %{"id" => "malipo-sig"}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-malipo-signature", "sha256=" <> String.duplicate("ab", 32))
        |> post(@path, body)

      assert response(conn, 400)
      assert all_enqueued(worker: ConfirmPayment) == []
    end

    test "a missing signature is rejected", %{conn: conn} do
      conn = post(conn, @path, %{"data" => %{"id" => "malipo-sig"}})

      assert response(conn, 400)
    end
  end

  defp sign(body, secret) do
    "sha256=" <>
      Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
  end
end
