defmodule Bonfire.UI.Messages.PubSub.Test do
  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui
  alias Bonfire.Social.Fake
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Likes
  alias Bonfire.Social.Graph.Follows
  alias Bonfire.Posts

  setup do
    me = fake_user!("meee")
    alice = fake_user!("alice")

    conn = conn(user: me)

    {:ok, conn: conn, alice: alice, me: me}
  end

  test "new reply appears in a message thread in real time", %{conn: conn, alice: alice, me: me} do
    # I create a thread with alice
    {:ok, %{id: thread_id} = post} =
      Bonfire.Messages.send(
        me,
        %{post_content: %{html_body: "Thread root"}},
        [alice.id]
      )

    # Visit the thread page 
    conn = visit(conn, "/messages/#{thread_id}")

    reply_content = "This is a live reply in the thread"

    # Alice replies in a separate process using Bonfire.Messages.send/3
    Task.start(fn ->
      Bonfire.Messages.send(
        alice,
        %{
          post_content: %{html_body: reply_content},
          reply_to: thread_id
        },
        [me.id]
      )
    end)

    conn
    |> assert_has_or_open_browser("[data-id=object_body]", text: reply_content, timeout: 3000)
  end

  test "new message I receive appears in my inbox in real time", %{
    conn: conn,
    me: me,
    alice: alice
  } do
    # Visit inbox as me
    conn = visit(conn, "/messages")

    message_content = "This is a live message from alice"

    # Send a message as Alice in a separate process
    Task.start(fn ->
      Bonfire.Messages.send(
        alice,
        %{post_content: %{html_body: message_content}},
        [me.id]
      )
    end)

    conn
    |> assert_has_or_open_browser("#message_threads", text: message_content, timeout: 3000)
  end

  test "new message I send appears in my own inbox in real time", %{
    conn: conn,
    me: me,
    alice: alice
  } do
    # Visit inbox as me
    conn = visit(conn, "/messages")

    message_content = "This is a live message from alice"

    # Send a message by me in a separate process
    Task.start(fn ->
      Bonfire.Messages.send(
        me,
        %{post_content: %{html_body: message_content}},
        [alice.id]
      )
    end)

    conn
    |> assert_has_or_open_browser("#message_threads", text: message_content, timeout: 3000)
  end
end
