defmodule ViewNinjasWeb.LinkPromptTest do
  use ExUnit.Case, async: true

  alias ViewNinjasWeb.LinkPrompt

  test "facebook post likes ask for a post link" do
    prompt = LinkPrompt.for_offer(%{platform: "facebook", outcome: "likes", target: "post"})

    assert prompt.label == "Paste the Facebook post link"
    assert prompt.placeholder == "https://facebook.com/yourpage/posts/123456789012345"
    assert prompt.hint =~ "/posts/"
  end

  test "facebook page likes ask for the page" do
    prompt = LinkPrompt.for_offer(%{platform: "facebook", outcome: "likes", target: "page"})

    assert prompt.label == "Paste the Facebook page link"
    assert prompt.placeholder == "https://facebook.com/yourpage"
    assert prompt.hint =~ "page itself"
  end

  test "instagram followers ask for a profile, and a reel asks for a reel" do
    profile = LinkPrompt.for_offer(%{platform: "instagram", outcome: "followers", target: ""})
    reel = LinkPrompt.for_offer(%{platform: "instagram", outcome: "likes", target: "reel"})

    assert profile.label == "Paste the Instagram profile link"
    assert profile.placeholder == "https://instagram.com/yourname"

    assert reel.label == "Paste the Instagram reel link"
    assert reel.placeholder == "https://instagram.com/reel/Cx4kExample"
  end

  test "tiktok likes and youtube subscribers pick a video and a channel" do
    likes = LinkPrompt.for_offer(%{platform: "tiktok", outcome: "likes"})
    subs = LinkPrompt.for_offer(%{platform: "youtube", outcome: "subscribers"})

    assert likes.placeholder =~ "/video/"
    assert subs.label == "Paste the YouTube channel link"
    assert subs.placeholder == "https://youtube.com/@yourchannel"
  end

  test "an unknown platform still names the thing, with a plain example" do
    prompt = LinkPrompt.for_offer(%{platform: "newnetwork", outcome: "likes", target: "post"})

    assert prompt.label == "Paste the post link"
    assert prompt.placeholder == "https://example.com/your-link"
  end
end
