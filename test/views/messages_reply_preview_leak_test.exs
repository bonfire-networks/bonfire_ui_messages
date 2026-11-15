defmodule Bonfire.UI.Messages.MessagesReplyPreviewLeakTest do
  @moduledoc """
  A person added to a conversation by a reply can read the reply but not the earlier message it answers, so the reply's preview of that message must not show it.
  """
  use Bonfire.UI.Messages.ConnCase, async: false
  use Bonfire.Common.Utils

  alias Bonfire.Messages

  @moduletag :ui

  @parent "Parent for A and B only zr71"
  @reply "Reply adding C zr72"

  setup do
    Process.put([:bonfire, :default_pagination_limit], 10)

    a = fake_user!(fake_account!())
    b = fake_user!(fake_account!())
    c = fake_user!(fake_account!())

    {:ok, parent} = Messages.send(a, %{post_content: %{html_body: @parent}}, b)

    {:ok, reply} =
      Messages.send(b, %{
        to_circles: [c.id],
        post_content: %{html_body: @reply},
        reply_to_id: parent.id
      })

    assert Bonfire.Boundaries.can?(b, :read, parent)
    refute Bonfire.Boundaries.can?(c, :read, parent)
    assert Bonfire.Boundaries.can?(c, :read, reply)

    {:ok, c: c, parent: parent, reply: reply}
  end

  defp refute_parent(session, parent) do
    PhoenixTest.unwrap(session, fn view ->
      html = Phoenix.LiveViewTest.render(view)
      refute html =~ @parent, "the parent message's text is on the page"
      html
    end)
  end

  test "C's view of the reply's discussion page doesn't carry the parent's id", %{
    c: c,
    parent: parent,
    reply: reply
  } do
    conn(user: c, account: c.account)
    |> visit("/discussion/#{reply.id}")
    |> wait_async()
    |> assert_has("main", text: @reply)
    |> PhoenixTest.unwrap(fn view ->
      html = Phoenix.LiveViewTest.render(view)
      refute html =~ parent.id, "the parent message's id is on the page"
      html
    end)
  end

  test "C's messages list shows the reply without the parent", %{c: c, parent: parent} do
    conn(user: c, account: c.account)
    |> visit("/messages")
    |> wait_async()
    |> assert_has("#message_threads", text: @reply)
    |> refute_parent(parent)
  end

  test "C's view of the reply's discussion page shows no parent", %{
    c: c,
    parent: parent,
    reply: reply
  } do
    conn(user: c, account: c.account)
    |> visit("/discussion/#{reply.id}")
    |> wait_async()
    |> assert_has("main", text: @reply)
    |> refute_parent(parent)
  end
end
