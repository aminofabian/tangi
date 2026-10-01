defmodule ViewNinjasWeb.LinkPrompt do
  @moduledoc """
  The words on the link field, chosen from the offer being ordered.

  A Facebook post and a Facebook page are different links, and so are an
  Instagram profile and a reel. The label names the thing, the placeholder
  shows a link of that shape, and the hint says where to copy it from.
  """
  use Gettext, backend: ViewNinjasWeb.Gettext

  @examples %{
    {"instagram", :profile} => "https://instagram.com/yourname",
    {"instagram", :post} => "https://instagram.com/p/Cx4kExample",
    {"instagram", :reel} => "https://instagram.com/reel/Cx4kExample",
    {"instagram", :comment} => "https://instagram.com/p/Cx4kExample",
    {"facebook", :page} => "https://facebook.com/yourpage",
    {"facebook", :profile} => "https://facebook.com/yourname",
    {"facebook", :post} => "https://facebook.com/yourpage/posts/123456789012345",
    {"facebook", :video} => "https://facebook.com/watch/?v=123456789012345",
    {"facebook", :reel} => "https://facebook.com/reel/123456789012345",
    {"facebook", :comment} => "https://facebook.com/yourpage/posts/123456789012345",
    {"tiktok", :profile} => "https://www.tiktok.com/@yourname",
    {"tiktok", :video} => "https://www.tiktok.com/@yourname/video/7234567890123456789",
    {"tiktok", :post} => "https://www.tiktok.com/@yourname/video/7234567890123456789",
    {"youtube", :channel} => "https://youtube.com/@yourchannel",
    {"youtube", :profile} => "https://youtube.com/@yourchannel",
    {"youtube", :video} => "https://youtube.com/watch?v=ytExample1",
    {"youtube", :post} => "https://youtube.com/watch?v=ytExample1",
    {"twitter", :profile} => "https://x.com/yourname",
    {"twitter", :post} => "https://x.com/yourname/status/1234567890123456789",
    {"x", :profile} => "https://x.com/yourname",
    {"x", :post} => "https://x.com/yourname/status/1234567890123456789",
    {"telegram", :channel} => "https://t.me/yourchannel",
    {"telegram", :profile} => "https://t.me/yourname",
    {"telegram", :post} => "https://t.me/yourchannel/128",
    {"spotify", :profile} => "https://open.spotify.com/artist/exampleArtistId",
    {"spotify", :track} => "https://open.spotify.com/track/exampleTrackId",
    {"threads", :profile} => "https://www.threads.net/@yourname",
    {"threads", :post} => "https://www.threads.net/@yourname/post/Cx4kExample",
    {"linkedin", :profile} => "https://www.linkedin.com/in/yourname",
    {"linkedin", :page} => "https://www.linkedin.com/company/yourcompany",
    {"linkedin", :post} => "https://www.linkedin.com/posts/yourname_example",
    {"whatsapp", :channel} => "https://whatsapp.com/channel/yourchannel",
    {"twitch", :channel} => "https://twitch.tv/yourname",
    {"twitch", :video} => "https://twitch.tv/videos/123456789",
    {"snapchat", :profile} => "https://www.snapchat.com/add/yourname",
    {"pinterest", :profile} => "https://pinterest.com/yourname",
    {"pinterest", :post} => "https://pinterest.com/pin/1234567890",
    {"reddit", :profile} => "https://www.reddit.com/user/yourname",
    {"reddit", :post} => "https://www.reddit.com/r/example/comments/abc123",
    {"soundcloud", :profile} => "https://soundcloud.com/yourname",
    {"soundcloud", :track} => "https://soundcloud.com/yourname/your-track",
    {"audiomack", :profile} => "https://audiomack.com/yourname",
    {"audiomack", :track} => "https://audiomack.com/yourname/song/your-track",
    {"boomplay", :profile} => "https://www.boomplay.com/artists/1234567",
    {"boomplay", :track} => "https://www.boomplay.com/songs/12345678",
    {"discord", :channel} => "https://discord.gg/yourserver",
    {"kwai", :profile} => "https://www.kwai.com/@yourname",
    {"kwai", :video} => "https://www.kwai.com/@yourname/video/123456789",
    {"likee", :profile} => "https://likee.video/@yourname",
    {"likee", :video} => "https://likee.video/@yourname/video/123456789"
  }

  @names %{
    "instagram" => "Instagram",
    "tiktok" => "TikTok",
    "youtube" => "YouTube",
    "facebook" => "Facebook",
    "twitter" => "X",
    "x" => "X",
    "telegram" => "Telegram",
    "spotify" => "Spotify",
    "threads" => "Threads",
    "linkedin" => "LinkedIn",
    "whatsapp" => "WhatsApp",
    "snapchat" => "Snapchat",
    "pinterest" => "Pinterest",
    "reddit" => "Reddit",
    "twitch" => "Twitch",
    "discord" => "Discord",
    "soundcloud" => "SoundCloud",
    "audiomack" => "Audiomack",
    "boomplay" => "Boomplay",
    "kwai" => "Kwai",
    "likee" => "Likee"
  }

  @doc """
  Label, placeholder, and hint for an offer.

  `target` wins when it is set: Facebook page likes and Facebook post likes
  ask for different links. With no target, the outcome decides — followers
  want a profile, views on YouTube want a video.
  """
  def for_offer(%{platform: platform, outcome: outcome} = offer) do
    platform = slug(platform)
    kind = kind(platform, slug(outcome), slug(Map.get(offer, :target)))

    %{
      label: label(platform, kind),
      placeholder: example(platform, kind),
      hint: hint(platform, kind)
    }
  end

  defp kind(_platform, _outcome, "page"), do: :page
  defp kind(_platform, _outcome, "post"), do: :post
  defp kind(_platform, _outcome, "video"), do: :video
  defp kind(_platform, _outcome, "reel"), do: :reel
  defp kind(_platform, _outcome, "profile"), do: :profile
  defp kind(_platform, _outcome, "channel"), do: :channel
  defp kind(_platform, _outcome, "comment"), do: :comment

  defp kind(platform, outcome, _target)
       when outcome in ~w(followers follower subscribers subscriber members member) do
    if platform in ~w(youtube twitch telegram discord), do: :channel, else: :profile
  end

  defp kind(platform, outcome, _target)
       when platform in ~w(spotify soundcloud audiomack boomplay) and
              outcome in ~w(plays play streams stream listens saves) do
    :track
  end

  defp kind(platform, outcome, _target)
       when outcome in ~w(views view likes like comments comment shares share saves) do
    if platform in ~w(youtube tiktok twitch kwai likee), do: :video, else: :post
  end

  defp kind(_platform, _outcome, _target), do: :profile

  defp label(platform, kind) do
    case Map.get(@names, platform) do
      nil -> gettext("Paste the %{thing} link", thing: thing(kind))
      name -> gettext("Paste the %{name} %{thing} link", name: name, thing: thing(kind))
    end
  end

  defp thing(:profile), do: gettext("profile")
  defp thing(:page), do: gettext("page")
  defp thing(:post), do: gettext("post")
  defp thing(:video), do: gettext("video")
  defp thing(:reel), do: gettext("reel")
  defp thing(:channel), do: gettext("channel")
  defp thing(:comment), do: gettext("comment")
  defp thing(:track), do: gettext("song")

  defp hint("facebook", :post) do
    gettext("Open the post, tap Share, then Copy link. A post link has /posts/ in it.")
  end

  defp hint("facebook", :page) do
    gettext("Open the page itself and copy that link. A post link will not do.")
  end

  defp hint("instagram", :reel) do
    gettext("Open the reel, tap Share, and copy the link. A reel link has /reel/ in it.")
  end

  defp hint("instagram", :post) do
    gettext("Open the post, tap Share, and copy the link. A post link has /p/ in it.")
  end

  defp hint("youtube", :video) do
    gettext("Open the video, tap Share, and copy the link. It has watch?v= in it.")
  end

  defp hint("tiktok", :video) do
    gettext("Open the video, tap Share, and copy the link. It has /video/ in it.")
  end

  defp hint(_platform, :profile) do
    gettext("Open the profile and copy the link from the address bar.")
  end

  defp hint(_platform, :page) do
    gettext("Open the page itself and copy that link.")
  end

  defp hint(_platform, :post) do
    gettext("Open the post, tap Share, and copy the link. Not the profile.")
  end

  defp hint(_platform, :video) do
    gettext("Open the video, tap Share, and copy the link.")
  end

  defp hint(_platform, :reel) do
    gettext("Open the reel, tap Share, and copy the link.")
  end

  defp hint(_platform, :channel) do
    gettext("Open the channel and copy the link from the address bar.")
  end

  defp hint(_platform, :comment) do
    gettext("Open the comment and copy its link.")
  end

  defp hint(_platform, :track) do
    gettext("Open the song and copy the link. Not the artist page.")
  end

  defp example(platform, kind) do
    Map.get(@examples, {platform, kind}) || "https://example.com/your-link"
  end

  defp slug(nil), do: ""
  defp slug(value), do: value |> to_string() |> String.trim() |> String.downcase()
end
