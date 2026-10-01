defmodule ViewNinjasWeb.UserSessionController do
  use ViewNinjasWeb, :controller

  alias ViewNinjas.Accounts
  alias ViewNinjas.RateLimit
  alias ViewNinjasWeb.ClientIp
  alias ViewNinjasWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, %{"_action" => "password_reset"} = params) do
    reset_password(conn, params)
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if RateLimit.allow_login?(ClientIp.from_conn(conn), identifier(email)) do
      if user = Accounts.get_user_by_email_and_password(email, password) do
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
      end
    else
      conn
      |> put_flash(:error, "Too many attempts. Please try again in a few minutes.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  # A password reset arrives as a form post from the emailed link, and on success
  # logs the user straight in: they proved control of the mailbox by opening the
  # link, so making them type their new password again would be pointless friction.
  #
  # The account comes from the token alone, never from the form, so a link cannot
  # be pointed at somebody else's address. `reset_user_password/2` deletes every
  # token inside the same transaction that changes the password, which makes the
  # link single-use: replaying it finds no user and lands on the error branch.
  defp reset_password(conn, %{"user" => %{"token" => token} = user_params}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")

      user ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "Password updated successfully!")
            |> UserAuth.log_in_user(user, user_params)

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Please choose a longer password and try again.")
            |> redirect(to: ~p"/users/reset-password/#{token}")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  # Login is email + password in v1 (scope.md §6); the phone/canonical
  # identifier shares this budget once phone login arrives.
  defp identifier(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
  defp identifier(other), do: other
end
