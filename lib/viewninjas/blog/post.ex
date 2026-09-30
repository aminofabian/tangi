defmodule ViewNinjas.Blog.Post do
  @moduledoc """
  One article — the pillar or a spoke of a cluster.

  A post is pure data: a title, the search-facing metadata, a lead, and a list of
  sections, each of which is a heading and a list of blocks. Keeping the prose as
  data rather than a template means the reading time, the table of contents and
  the schema.org markup are all derived from the same source, so they cannot
  drift apart. The web layer (`ViewNinjasWeb.BlogLive`) turns the blocks into
  HTML.

  ## Blocks

  A section's `:blocks` is a list of tuples:

    * `{:p, text}` - a paragraph
    * `{:h3, text}` - a subheading inside the section
    * `{:ul, [text]}` - a bulleted list
    * `{:ol, [text]}` - a numbered list
    * `{:table, %{head: [..], rows: [[..]]}}` - a data table
    * `{:callout, text}` - a highlighted aside
    * `{:cta, %{text: text, href: path, label: label}}` - a call to action

  Any `text` may carry inline links written `[label](/path)`, which the web layer
  renders as `.link` elements so they use live navigation.
  """

  @enforce_keys [:slug, :cluster, :kind, :title, :meta_title, :description, :updated_on]
  defstruct [
    :slug,
    :cluster,
    :kind,
    :title,
    :meta_title,
    :description,
    :eyebrow,
    :updated_on,
    keywords: [],
    intro: [],
    sections: [],
    faqs: []
  ]

  @type slug :: String.t()
  @type kind :: :pillar | :spoke
  @type block ::
          {:p, String.t()}
          | {:h3, String.t()}
          | {:ul, [String.t()]}
          | {:ol, [String.t()]}
          | {:table, map()}
          | {:callout, String.t()}
          | {:cta, map()}

  @type section :: %{
          id: String.t(),
          heading: String.t(),
          blocks: [block()],
          toc: boolean()
        }

  @type faq :: %{question: String.t(), answer: String.t()}

  @type t :: %__MODULE__{
          slug: slug(),
          cluster: ViewNinjas.Blog.Cluster.slug(),
          kind: kind(),
          title: String.t(),
          meta_title: String.t(),
          description: String.t(),
          eyebrow: String.t() | nil,
          updated_on: Date.t(),
          keywords: [String.t()],
          intro: [String.t()],
          sections: [section()],
          faqs: [faq()]
        }

  @doc "The post's public path, used in links and the sitemap."
  @spec path(t()) :: String.t()
  def path(%__MODULE__{slug: slug}), do: "/blog/#{slug}"

  @doc """
  The sections that belong in the table of contents, in order.

  The FAQ and the closing call to action are real sections but have nothing to
  navigate to, so a post marks them `toc: false`.
  """
  @spec toc(t()) :: [section()]
  def toc(%__MODULE__{sections: sections}), do: Enum.filter(sections, &Map.get(&1, :toc, true))

  @doc "An estimate of reading time in whole minutes, floored at one."
  @spec reading_minutes(t()) :: pos_integer()
  def reading_minutes(%__MODULE__{} = post) do
    post
    |> word_count()
    |> Kernel.div(200)
    |> max(1)
  end

  @doc "Every word a reader actually reads, for the reading-time estimate."
  @spec word_count(t()) :: non_neg_integer()
  def word_count(%__MODULE__{} = post) do
    [post.intro, post.faqs, post.sections]
    |> text_chunks()
    |> Enum.map(&count_words/1)
    |> Enum.sum()
  end

  defp text_chunks(chunks) when is_list(chunks), do: Enum.flat_map(chunks, &text_chunks/1)
  defp text_chunks(%{answer: answer, question: question}), do: [question, answer]
  defp text_chunks(%{blocks: blocks} = section), do: [section[:heading] | text_chunks(blocks)]
  defp text_chunks(text) when is_binary(text), do: [text]

  defp text_chunks({:ul, items}), do: items
  defp text_chunks({:ol, items}), do: items
  defp text_chunks({_tag, text}) when is_binary(text), do: [text]
  defp text_chunks({:table, %{head: head, rows: rows}}), do: head ++ List.flatten(rows)
  defp text_chunks({:cta, %{text: text}}), do: [text]
  defp text_chunks(_), do: []

  defp count_words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
