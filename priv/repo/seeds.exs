# Seeds for local development. Run with `mix ecto.setup`, `mix ecto.reset`, or
# directly: `mix run priv/repo/seeds.exs`.
#
# Idempotent: rows are matched on email, so running it twice changes nothing.
# Development only by default. In production nothing is created unless
# SEED_ADMIN_EMAIL is set explicitly, so a deploy can never invent an account.

alias ViewNinjas.Accounts

admin_email = System.get_env("SEED_ADMIN_EMAIL", "ops@example.com")
admin_phone = System.get_env("SEED_ADMIN_PHONE", "0712345678")
admin_password = System.get_env("SEED_ADMIN_PASSWORD", "correct horse battery")

customer_email = System.get_env("SEED_CUSTOMER_EMAIL", "customer@example.com")
customer_phone = System.get_env("SEED_CUSTOMER_PHONE", "0722000111")
customer_password = System.get_env("SEED_CUSTOMER_PASSWORD", "correct horse battery")

seed_admin? = Mix.env() != :prod or not is_nil(System.get_env("SEED_ADMIN_EMAIL"))
seed_customer? = Mix.env() != :prod

if seed_admin? do
  if user = Accounts.get_user_by_email(admin_email) do
    IO.puts("Seeds: kept existing #{user.role} #{user.email}")
  else
    {:ok, user} =
      Accounts.create_staff_user(%{
        email: admin_email,
        phone: admin_phone,
        password: admin_password,
        role: :super_admin
      })

    IO.puts("Seeds: created super_admin #{user.email} (#{user.phone})")
  end
end

if seed_customer? do
  if user = Accounts.get_user_by_email(customer_email) do
    IO.puts("Seeds: kept existing #{user.role} #{user.email}")
  else
    {:ok, user} =
      Accounts.register_user(%{
        email: customer_email,
        phone: customer_phone,
        password: customer_password
      })

    IO.puts("Seeds: created customer #{user.email} (#{user.phone})")
  end
end

if not seed_admin? and not seed_customer? do
  IO.puts("Seeds: skipped in production (set SEED_ADMIN_EMAIL to seed a staff account).")
end

# A baseline pricing version and FX rate, so a fresh development database quotes
# from a recorded row rather than only the §7 defaults. Idempotent.
if Mix.env() != :prod do
  alias ViewNinjas.Pricing

  actor = Accounts.get_user_by_email(admin_email)

  if Pricing.current_settings() do
    IO.puts("Seeds: kept the existing pricing version")
  else
    {:ok, _} =
      Pricing.append_settings(
        %{margin_bps: 13_000, buffer_bps: 300, reason: "Initial §7 defaults"},
        actor
      )

    IO.puts("Seeds: recorded the initial pricing version (130% / 3%)")
  end

  if Pricing.current_fx() do
    IO.puts("Seeds: kept the existing FX rate")
  else
    {:ok, _} = Pricing.record_fx_rate(%{rate_ppm: 129_400_000, source: "fixture"}, actor)
    IO.puts("Seeds: recorded the fixture FX rate (129.40)")
  end
end
