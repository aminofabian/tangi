defmodule ViewNinjas.Blog do
  @moduledoc """
  The blog: a small, hand-written library of content clusters (scope.md §11).

  Articles live in the source, not the database, and are compiled in. That keeps
  the marketing copy reviewed like code — a change to a price or a claim goes
  through the same pull request and the same tests as the rest of the site — and
  it means every page is a plain server render a crawler can read without
  running JavaScript, exactly like the market.

  Each cluster is a module under `ViewNinjas.Blog.Clusters` exposing a `cluster/0`
  and a `posts/0`; this module is the one place that knows them all, so the
  router, the sitemap and the LiveView share a single list.
  """

  alias ViewNinjas.Blog.{Cluster, Post}

  @clusters [
    ViewNinjas.Blog.Clusters.BuyYoutubeViewsKenya,
    ViewNinjas.Blog.Clusters.TopYoutubeViewsProvidersKenya,
    ViewNinjas.Blog.Clusters.TopTiktokFollowersProvidersKenya
  ]

  @doc "Every cluster, in the order they are published."
  @spec list_clusters() :: [Cluster.t()]
  def list_clusters, do: Enum.map(@clusters, & &1.cluster())

  @doc "The cluster with this slug, or nil."
  @spec get_cluster(Cluster.slug() | term()) :: Cluster.t() | nil
  def get_cluster(slug) when is_binary(slug), do: Enum.find(list_clusters(), &(&1.slug == slug))
  def get_cluster(_slug), do: nil

  @doc """
  Every post in every cluster, each cluster's pillar first.

  The order is the reading order the blog index shows, so it is the order a
  crawler meets the topic in too.
  """
  @spec list_posts() :: [Post.t()]
  def list_posts, do: Enum.flat_map(@clusters, &ordered_posts/1)

  @doc "The post with this slug, or nil."
  @spec get_post(Post.slug() | term()) :: Post.t() | nil
  def get_post(slug) when is_binary(slug), do: Enum.find(list_posts(), &(&1.slug == slug))
  def get_post(_slug), do: nil

  @doc "Every post in a cluster, pillar first, or `[]` for an unknown cluster."
  @spec posts_in_cluster(Cluster.slug() | term()) :: [Post.t()]
  def posts_in_cluster(slug) do
    case Enum.find(@clusters, &(&1.cluster().slug == slug)) do
      nil -> []
      cluster -> ordered_posts(cluster)
    end
  end

  @doc "A cluster's pillar article."
  @spec pillar(Cluster.slug() | term()) :: Post.t() | nil
  def pillar(slug), do: Enum.find(posts_in_cluster(slug), &(&1.kind == :pillar))

  @doc "A cluster's supporting articles, in reading order."
  @spec spokes(Cluster.slug() | term()) :: [Post.t()]
  def spokes(slug), do: Enum.filter(posts_in_cluster(slug), &(&1.kind == :spoke))

  @doc """
  The other articles a reader should see next: the rest of the post's own
  cluster, pillar first, so a spoke always points back up to its pillar.
  """
  @spec related(Post.t()) :: [Post.t()]
  def related(%Post{cluster: cluster, slug: slug}) do
    Enum.reject(posts_in_cluster(cluster), &(&1.slug == slug))
  end

  defp ordered_posts(cluster_module) do
    posts = cluster_module.posts()

    {pillars, spokes} = Enum.split_with(posts, &(&1.kind == :pillar))
    pillars ++ spokes
  end
end
