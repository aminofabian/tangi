defmodule ViewNinjas.Vault do
  @moduledoc """
  The application's encryption vault (Cloak), used to keep supplier API keys
  encrypted at rest (scope.md §12).

  The cipher key comes from configuration: a fixed development key, and
  `CLOAK_KEY` in production (see config/runtime.exs). Rotating it is a
  migration rather than a config change, because rows encrypted with the old key
  have to be re-encrypted while it is still present.
  """
  use Cloak.Vault, otp_app: :viewninjas
end
