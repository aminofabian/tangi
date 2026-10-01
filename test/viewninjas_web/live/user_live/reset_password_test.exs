defmodule ViewNinjasWeb.UserLive.ResetPasswordTest do
  @moduledoc """
  Setting a new password from an emailed reset link.

  The two properties worth guarding are that a reset **logs the user in** (they
  proved the mailbox by opening the link) and that the link is **single-use** —
  `reset_user_password/2` deletes every token in the same transaction that changes
  the password, so a replayed link must not work.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts

  setup do
    %{user: user_fixture()}
  end

  defp reset_token(user) do
    extract_user_token(fn url ->
      Accounts.deliver_user_reset_password_instructions(user, url)
    end)
  end

  defp submit_new_password(lv, token, password) do
    form =
      form(lv, "#reset_password_form", %{
        "user" => %{
          "token" => token,
          "password" => password,
          "password_confirmation" => password
        }
      })

    render_submit(form)

    form
  end

  describe "the reset screen" do
    test "renders the form for a valid link", %{conn: conn, user: user} do
      token = reset_token(user)

      {:ok, lv, html} = live(conn, ~p"/users/reset-password/#{token}")

      assert html =~ "Set a new password"
      assert has_element?(lv, "#reset_password_form")
      assert has_element?(lv, "#reset_password_form input[name='user[password]']")
      assert has_element?(lv, "#reset_password_form input[name='user[password_confirmation]']")
      # The token travels in a hidden field, not the URL the user can tamper with.
      assert has_element?(lv, "#reset_password_form input[name='user[token]'][value='#{token}']")
    end

    test "an invalid or expired link goes back to log in", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/reset-password/not-a-real-token")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Reset password link is invalid or it has expired"
      refute html =~ "Set a new password"
    end
  end

  describe "resetting the password" do
    test "sets the new password and logs the user in", %{conn: conn, user: user} do
      token = reset_token(user)
      new_password = "a brand new long password"

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      conn =
        lv
        |> submit_new_password(token, new_password)
        |> follow_trigger_action(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)

      # The new password works and the old one does not.
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "the link cannot be used twice", %{conn: conn, user: user} do
      token = reset_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      lv
      |> submit_new_password(token, "a brand new long password")
      |> follow_trigger_action(conn)

      # Replaying the same link finds no user, because the reset consumed it.
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/reset-password/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Reset password link is invalid or it has expired"
    end

    test "a short password is refused and the link still works", %{conn: conn, user: user} do
      token = reset_token(user)

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      conn =
        lv
        |> submit_new_password(token, "short")
        |> follow_trigger_action(conn)

      # The controller refuses it and sends the user back to the same form.
      assert redirected_to(conn) == ~p"/users/reset-password/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "longer password"

      # The failed attempt did not consume the link or change the password.
      assert Accounts.get_user_by_reset_password_token(token)
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "changing the password expires the user's other sessions", %{conn: conn, user: user} do
      # A session token issued before the reset must not survive it.
      old_session = Accounts.generate_user_session_token(user)

      token = reset_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      lv
      |> submit_new_password(token, "a brand new long password")
      |> follow_trigger_action(conn)

      refute Accounts.get_user_by_session_token(old_session)
    end
  end
end
