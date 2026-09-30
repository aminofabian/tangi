defmodule ViewNinjas.Costs do
  @moduledoc """
  The shop's own costs (scope.md §6, §10): hosting, a domain, anything that is not
  a customer's order. SMS and the payment fee are derived from their own rows, so
  they are not entered here.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Insight.Cost
  alias ViewNinjas.Repo

  @doc "The recorded costs, newest first."
  @spec list_costs(keyword()) :: [Cost.t()]
  def list_costs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Cost
    |> order_by([c], desc: c.incurred_on, desc: c.id)
    |> limit(^limit)
    |> preload(:actor)
    |> Repo.all()
  end

  @doc "Records a cost, stamping who entered it."
  @spec create_cost(map(), User.t() | nil) :: {:ok, Cost.t()} | {:error, Ecto.Changeset.t()}
  def create_cost(params, actor) do
    params = Map.put_new(params, "actor_id", actor && actor.id)

    %Cost{}
    |> Cost.changeset(params)
    |> Repo.insert()
  end

  def get_cost(id), do: Repo.get(Cost, id)

  def change_cost(%Cost{} = cost, attrs \\ %{}), do: Cost.changeset(cost, attrs)

  def delete_cost(%Cost{} = cost), do: Repo.delete(cost)
end
