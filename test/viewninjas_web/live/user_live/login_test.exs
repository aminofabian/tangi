defmodule ViewNinjasWeb.UserLive.LoginTest do
  @moduledoc """
  Logging in (scope.md §6): one email field, and a switch between the password and
  the emailed link.

  The screen used to carry two forms and two email inputs; these cases pin the
  shape that replaced it — one identity, one method — because "which box do I
  fill in?" was the whole problem.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  describe "login page" do
    test "asks for the email once", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert has_element?(lv, "a[href='/users/reset-password']")

      # One form, one email input — the two-input layout was the confusion.
      assert has_element?(lv, "#login_form")
      refute has_element?(lv, "#login_form_magic")
      refute has_element?(lv, "#login_form_password")

      emails =
        lv
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.filter("#login_form input[type=email]")

      assert length(emails) == 1
    end

    test "offers both ways in, with password chosen first", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login-method-password")
      assert has_element?(lv, "#login-method-link")

      assert html =~ ~s(aria-pressed="true")

      # Password is the default, so its fields are already there.
      assert has_element?(lv, "#login-password-fields")
      assert has_element?(lv, "#login_form input[type=password]")
    end
  end

  describe "choosing how to log in" do
    test "switching to a link shows the hint and drops the password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      html = lv |> element("#login-method-link") |> render_click()

      assert html =~ ~s(aria-pressed="true")
      assert has_element?(lv, "#login-link-hint")
      refute has_element?(lv, "#login-password-fields")
      refute has_element?(lv, "#login_form input[type=password]")
      # The email box is never taken away — that was the original problem.
      assert has_element?(lv, "#login_form input[type=email]")
    end

    test "switching back restores the password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> element("#login-method-link") |> render_click()
      lv |> element("#login-method-password") |> render_click()

      assert has_element?(lv, "#login-password-fields")
      refute has_element?(lv, "#login-link-hint")
    end

    test "the button says what it will do", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert lv |> element("#login-submit") |> render() =~ "Log in"

      lv |> element("#login-method-link") |> render_click()

      assert lv |> element("#login-submit") |> render() =~ "Send me a login link"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> element("#login-method-link") |> render_click()

      {:ok, _lv, html} =
        form(lv, "#login_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert ViewNinjas.Repo.get_by!(ViewNinjas.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> element("#login-method-link") |> render_click()

      {:ok, _lv, html} =
        form(lv, "#login_form", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "a checked 'keep me logged in' is honoured", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form",
          user: %{
            email: user.email,
            password: valid_user_password(),
            remember_me: "true"
          }
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert conn.resp_cookies["_view_ninjas_web_user_remember_me"]
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: "true"}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "the password branch really posts, rather than staying in the LiveView", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form = form(lv, "#login_form", user: %{email: "a@b.test", password: "whatever"})

      # The trigger action is what hands off to the controller that issues the
      # session cookie; without it the login would silently do nothing.
      assert render_submit(form) =~ ~r/phx-trigger-action/
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Create an account"
    end

    test "the reset link goes to the forgot-password screen", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        lv
        |> element("main a", "Forgot your password?")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/reset-password")

      assert html =~ "Forgot your password?"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert has_element?(lv, "#login-method-link")

      assert has_element?(lv, "#login_form input[type=email][value='#{user.email}']")
    end
  end
end
