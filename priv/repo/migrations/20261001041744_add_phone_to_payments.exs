defmodule ViewNinjas.Repo.Migrations.AddPhoneToPayments do
  use Ecto.Migration

  # The number the prompt actually went to, when it is not the account's own
  # (a customer may pay from a second phone). Nullable: rows written before this
  # column fell back to the account phone, and so do we when it is null.
  def change do
    alter table(:payments) do
      add :phone, :string
    end
  end
end
