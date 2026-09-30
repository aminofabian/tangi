defmodule ViewNinjas.Encrypted.Binary do
  @moduledoc """
  An Ecto type that transparently encrypts a binary column with
  `ViewNinjas.Vault`. Supplier API keys are stored with this, so the plaintext
  key exists only in memory and in the request, never in the table.
  """
  use Cloak.Ecto.Binary, vault: ViewNinjas.Vault
end
