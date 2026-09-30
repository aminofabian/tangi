defmodule ViewNinjas.SettingsTest do
  @moduledoc """
  The super-admin settings store (build-plan.md M12, scope.md §7, §11): encrypted
  at rest, database-then-environment, and secrets never read back into a screen.
  """

  # Mutates global application env for the fallback assertions, so keep it serial.
  use ViewNinjas.DataCase, async: false

  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Settings

  setup do
    for {app, key} <- [
          {:viewninjas, :sms},
          {:viewninjas, ViewNinjas.Payments.Malipo},
          {:viewninjas, :malipo_webhook_secret},
          {:viewninjas, :mailer_from}
        ] do
      previous = Application.get_env(app, key)
      on_exit(fn -> Application.put_env(app, key, previous) end)
    end

    :ok
  end

  describe "put/3 and the store" do
    test "stores the value encrypted, never in the clear" do
      actor = super_admin_fixture()

      assert {:ok, _setting} = Settings.put("malipo_secret_key", "sk_live_secret", actor)

      assert Settings.malipo_secret_key() == "sk_live_secret"

      # The column is ciphertext: the plaintext is not in the row.
      %{rows: [[raw]]} =
        Repo.query!("select encrypted_value from app_settings where key = $1", [
          "malipo_secret_key"
        ])

      refute raw =~ "sk_live_secret"
    end

    test "records who changed it" do
      actor = super_admin_fixture()
      {:ok, setting} = Settings.put("textsms_shortcode", "VNI", actor)

      assert setting.updated_by_id == actor.id

      other = super_admin_fixture()
      {:ok, updated} = Settings.put("textsms_shortcode", "VN2", other)
      assert updated.updated_by_id == other.id
    end

    test "clear/1 removes the override" do
      {:ok, _} = Settings.put("textsms_shortcode", "VNI", nil)
      assert Settings.textsms_shortcode() == "VNI"

      :ok = Settings.clear("textsms_shortcode")
      assert Settings.textsms_shortcode() == nil
    end

    test "an integer setting refuses a non-number" do
      assert {:error, :not_an_integer} = Settings.put("sms_daily_cap_micros", "lots", nil)

      assert {:ok, _} = Settings.put("sms_daily_cap_micros", "1000000", nil)
      assert Settings.sms_daily_cap_micros() == 1_000_000
    end

    test "an unknown key is refused" do
      assert {:error, :unknown_key} = Settings.put("nonsense", "x", nil)
    end
  end

  describe "put_many/2" do
    test "writes the values given and leaves the blanks alone" do
      {:ok, _} = Settings.put("textsms_api_key", "key-1", nil)

      assert {:ok, 1} =
               Settings.put_many(
                 %{"textsms_partner_id" => "1234", "textsms_api_key" => ""},
                 nil
               )

      assert Settings.textsms_api_key() == "key-1"
      assert Settings.textsms_partner_id() == "1234"
    end
  end

  describe "the environment is the fallback" do
    test "a database value overrides the environment" do
      Application.put_env(:viewninjas, ViewNinjas.Payments.Malipo, secret_key: "env-key")
      assert Settings.malipo_secret_key() == "env-key"

      {:ok, _} = Settings.put("malipo_secret_key", "db-key", nil)
      assert Settings.malipo_secret_key() == "db-key"
    end

    test "webhook secret falls back to the environment" do
      Application.put_env(:viewninjas, :malipo_webhook_secret, "whsec_env")
      assert Settings.malipo_webhook_secret() == "whsec_env"

      {:ok, _} = Settings.put("malipo_webhook_secret", "whsec_db", nil)
      assert Settings.malipo_webhook_secret() == "whsec_db"
    end

    test "mailer_from is a name and an address" do
      {:ok, _} = Settings.put("mailer_from", "hello@viewninjas.test", nil)
      assert Settings.mailer_from() == {"ViewNinjas", "hello@viewninjas.test"}
    end

    test "defaults apply when nothing is set" do
      assert Settings.fx_source_path() == "rates.KES"
      assert Settings.insight_hash_salt() != nil
      assert Settings.sms_daily_cap_micros() == 20_000_000
    end
  end

  describe "entries/0 for the screen" do
    test "never returns a secret's value" do
      {:ok, _} = Settings.put("malipo_secret_key", "sk_live_secret", nil)

      entry = Enum.find(Settings.entries(), &(&1.key == "malipo_secret_key"))

      assert entry.secret
      assert entry.stored
      assert entry.value == nil
    end

    test "a non-secret returns its stored value" do
      {:ok, _} = Settings.put("malipo_base_url", "https://malipo.example", nil)

      entry = Enum.find(Settings.entries(), &(&1.key == "malipo_base_url"))

      refute entry.secret
      assert entry.value == "https://malipo.example"
    end

    test "reports whether a value is in force from the environment" do
      Application.put_env(:viewninjas, ViewNinjas.Payments.Malipo, secret_key: "env-key")

      entry = Enum.find(Settings.entries(), &(&1.key == "malipo_secret_key"))

      refute entry.stored
      assert entry.effective
    end
  end
end
