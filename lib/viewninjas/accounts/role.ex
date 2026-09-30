defmodule ViewNinjas.Accounts.Role do
  @moduledoc """
  The roles a user can hold (scope.md §6).

    * `:customer` — buys.
    * `:admin` — runs the catalog and orders.
    * `:super_admin` — also holds the money knobs (margin, buffer, FX, rounding).

  One person can be both an admin and a super-admin: `super_admin` implies
  `admin` for every check the back office makes. Public sign-up only ever
  produces `:customer`; staff roles are created by a mix task, never by a
  form.
  """

  @type t :: :customer | :admin | :super_admin

  @roles [:customer, :admin, :super_admin]

  @doc "All roles, as the atoms stored on `users.role`."
  @spec all() :: [t()]
  def all, do: @roles

  @doc "Whether the role may open the back office (admin or super_admin)."
  @spec staff?(term()) :: boolean()
  def staff?(role), do: role in [:admin, :super_admin]

  @doc "Whether the role may change the money knobs."
  @spec super_admin?(term()) :: boolean()
  def super_admin?(role), do: role == :super_admin

  @doc """
  Parses a role from an atom or a string, for scripts and mix tasks.

      iex> ViewNinjas.Accounts.Role.parse("admin")
      {:ok, :admin}

      iex> ViewNinjas.Accounts.Role.parse(:super_admin)
      {:ok, :super_admin}

      iex> ViewNinjas.Accounts.Role.parse("root")
      :error
  """
  @spec parse(term()) :: {:ok, t()} | :error
  def parse(role) when role in @roles, do: {:ok, role}

  def parse(role) when is_binary(role) do
    case Enum.find(@roles, &(Atom.to_string(&1) == role)) do
      nil -> :error
      role -> {:ok, role}
    end
  end

  def parse(_), do: :error
end
