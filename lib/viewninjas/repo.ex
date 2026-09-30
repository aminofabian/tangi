defmodule ViewNinjas.Repo do
  use Ecto.Repo,
    otp_app: :viewninjas,
    adapter: Ecto.Adapters.Postgres
end
