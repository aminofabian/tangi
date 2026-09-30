defmodule Mix.Tasks.Viewninjas.CreateAdmin do
  @shortdoc "Creates an admin or super_admin account"

  @moduledoc """
  Creates a staff account. This is the only path to an `admin` or
  `super_admin` role — public sign-up always produces a `:customer`
  (build-plan.md M1, scope.md §6).

      mix viewninjas.create_admin \\
        --email ops@example.com \\
        --phone 0712345678 \\
        --password "a long enough password" \\
        --role admin

  Options:

    * `--email` (required)
    * `--phone` (required; any Kenyan spelling, stored canonically as `254…`)
    * `--password` (required; at least 12 characters)
    * `--role` (required; `admin` or `super_admin`)
  """

  use Mix.Task

  alias ViewNinjas.Accounts
  alias ViewNinjas.Accounts.Role

  @switches [email: :string, phone: :string, password: :string, role: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] ->
        Mix.raise("Invalid options: #{inspect(invalid)}")

      missing = missing_option(opts) ->
        Mix.raise("Missing required option --#{missing}")

      true ->
        create(opts)
    end
  end

  defp missing_option(opts) do
    Enum.find([:email, :phone, :password, :role], fn key -> is_nil(opts[key]) end)
  end

  defp create(opts) do
    with {:ok, role} <- parse_staff_role(opts[:role]),
         {:ok, user} <-
           Accounts.create_staff_user(%{
             email: opts[:email],
             phone: opts[:phone],
             password: opts[:password],
             role: role
           }) do
      Mix.shell().info("Created #{role} #{user.email} (#{user.phone})")
    else
      :error ->
        Mix.raise("--role must be admin or super_admin")

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise(
          "Could not create the account: #{inspect(Ecto.Changeset.traverse_errors(changeset, &error_message/1))}"
        )
    end
  end

  defp parse_staff_role(value) do
    case Role.parse(value) do
      {:ok, role} -> if Role.staff?(role), do: {:ok, role}, else: :error
      :error -> :error
    end
  end

  defp error_message({message, opts}), do: "#{message} (#{inspect(opts)})"
end
