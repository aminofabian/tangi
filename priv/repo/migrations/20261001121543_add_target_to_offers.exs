defmodule ViewNinjas.Repo.Migrations.AddTargetToOffers do
  use Ecto.Migration

  @moduledoc """
  Give an offer somewhere to record **what** the customer links to.

  Platform and outcome could not tell a Facebook page like from a Facebook post
  like: both are `facebook` + `likes`, so the unique index made the second one
  impossible to publish and both were sold as "Facebook likes". The target — the
  noun the link points at — is the missing dimension.

  It is an empty string by default, not null, so every existing offer keeps its
  identity, its title and its place in the shop without a backfill, and the index
  below reproduces the old uniqueness exactly for offers that have no target.
  """

  def change do
    # `null: false` with a default, so the new column is never a special case.
    alter table(:offers) do
      add :target, :string, null: false, default: ""
    end

    # facebook + likes + "page" and facebook + likes + "post" are now two rows.
    drop unique_index(:offers, [:platform, :outcome])
    create unique_index(:offers, [:platform, :outcome, :target])
  end
end
