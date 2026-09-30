defmodule ViewNinjas.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.{Phone, Role}

  schema "users" do
    field :email, :string
    field :phone, :string
    field :role, Ecto.Enum, values: Role.all(), default: :customer
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :phone_verified_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for public registration: email, phone and password.

  The role is never taken from the caller — public sign-up always produces a
  `:customer`. The account is created confirmed, because the trustworthy
  verification in this market is the phone (M2), not the email.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :phone, :password])
    |> validate_email(opts)
    |> validate_phone(opts)
    |> validate_password(opts)
    |> put_change(:role, :customer)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A changeset for staff accounts created by a mix task, never by a form. It is
  the only changeset that accepts a role.
  """
  def admin_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :phone, :password, :role])
    |> require_role()
    |> validate_email(opts)
    |> validate_phone(opts)
    |> validate_password(opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  # `role` has a schema default (`:customer`), so `validate_required/2` would
  # never fire. Staff creation must state the role explicitly.
  defp require_role(changeset) do
    if get_change(changeset, :role) do
      changeset
    else
      add_error(changeset, :role, "can't be blank")
    end
  end

  @doc """
  A changeset for changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A changeset for changing the phone number.

  Changing the number makes it unverified again: the code that proved the old
  number says nothing about the new one.
  """
  def phone_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:phone])
    |> validate_phone(opts)
    |> maybe_reset_verification()
  end

  defp maybe_reset_verification(changeset) do
    if get_change(changeset, :phone) do
      put_change(changeset, :phone_verified_at, nil)
    else
      changeset
    end
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, ViewNinjas.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_phone(changeset, opts) do
    case get_field(changeset, :phone) do
      blank when blank in [nil, ""] ->
        validate_required(changeset, [:phone])

      phone ->
        case Phone.normalize(phone) do
          {:ok, canonical} ->
            changeset
            |> put_change(:phone, canonical)
            |> validate_length(:phone, is: 12)
            |> maybe_validate_unique_phone(opts)

          {:error, :invalid_phone} ->
            add_error(
              changeset,
              :phone,
              "is not a valid Kenyan number, for example 0712 345 678"
            )
        end
    end
  end

  defp maybe_validate_unique_phone(changeset, opts) do
    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:phone, ViewNinjas.Repo)
      |> unique_constraint(:phone)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%ViewNinjas.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
