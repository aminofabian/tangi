defmodule ViewNinjas.Blog.Cluster do
  @moduledoc """
  A content cluster: one pillar article and the spokes that support it.

  A cluster is the unit a search engine sees as a topic — the pillar answers the
  broad question and every spoke answers a narrower one, cross-linking so both
  the reader and the crawler can find the whole set from any single page
  (scope.md §11's "public SEO pages").
  """

  @enforce_keys [:slug, :title, :description]
  defstruct [:slug, :title, :description, :keyword, :eyebrow]

  @type slug :: String.t()

  @type t :: %__MODULE__{
          slug: slug(),
          title: String.t(),
          description: String.t(),
          keyword: String.t() | nil,
          eyebrow: String.t() | nil
        }
end
