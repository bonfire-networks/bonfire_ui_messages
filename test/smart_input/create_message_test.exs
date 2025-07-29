defmodule Bonfire.UI.Messages.CreateMessageTest do
  use Bonfire.UI.Messages.ConnCase, async: true
  use Bonfire.Common.Utils
  import Bonfire.Files.Simulation

  alias Bonfire.Social.Fake
  alias Bonfire.Messages
  alias Bonfire.Social.Graph.Follows
  alias Bonfire.Files.Test

  setup do
    account = fake_account!()
    me = fake_user!(account)
    recipient = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, recipient: recipient}
  end

  test "message shows up in sender's message threads list", %{
    conn: conn,
    me: me,
    recipient: recipient
  } do
    content = "here is an epic html message"

    attrs = %{
      post_content: %{
        html_body: content
      }
    }

    {:ok, _op} = Messages.send(me, attrs, recipient)

    conn
    |> visit("/messages")
    |> assert_has_or_open_browser("#message_threads", text: content)
  end

  test "message shows up in recipient's message threads list", %{
    conn: conn,
    me: me,
    recipient: recipient,
    account: account
  } do
    content = "here is an epic html message"

    attrs = %{
      post_content: %{
        html_body: content
      }
    }

    {:ok, op} = Messages.send(me, attrs, recipient)
    # IO.inspect(op, label: "Message Operation")
    # Create new connection as recipient
    recipient_conn = conn(user: recipient, account: account)

    recipient_conn
    |> visit("/messages")
    |> assert_has_or_open_browser("#message_threads", text: content)
  end

  test "does not show up on my profile timeline", %{conn: conn, me: me, recipient: recipient} do
    content = "here is an epic html message"

    session = visit(conn, "/settings")

    {:ok, view, _html} = live(conn, "/settings")
    live_async_wait(view)

    assert sent =
             view
             |> form("#smart_input form")
             |> render_submit(%{
               "create_object_type" => "message",
               "to_circles" => [id(recipient)],
               "post" => %{"post_content" => %{"html_body" => content}}
             })

    session
    |> visit("/user")
    |> refute_has("[data-id=feed]", text: content)
  end

  test "recipient can send reply, which appears instantly on thread page", %{
    me: me,
    recipient: recipient,
    conn: conn
  } do
    attrs = %{
      post_content: %{
        summary: "summary",
        name: "test message name",
        html_body: "first message"
      }
    }

    assert {:ok, op} =
             Messages.send(me, attrs, recipient)

    content = "epic reply"

    reply = %{
      post_content: %{html_body: content},
      reply_to_id: op.id
    }

    next = "/messages/#{id(op)}"
    # |> IO.inspect
    assert {:ok, re} =
             Messages.send(me, reply, recipient)

    conn
    |> visit(next)
    |> assert_has_or_open_browser("article", text: content)
  end

  describe "DM filtering tabs" do
    test "All tab shows all messages by default", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "message from unfollowed user"

      attrs = %{
        post_content: %{html_body: content}
      }

      {:ok, _op} = Messages.send(recipient, attrs, me)

      conn
      |> visit("/messages?tab=all")
      |> assert_has_or_open_browser("#message_threads", text: content)
    end

    test "Followed Only tab shows only messages from followed users", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      # Create another user that me doesn't follow
      unfollowed_user = fake_user!(account)

      # Create messages from both users
      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      # Follow the recipient
      {:ok, _follow} = Follows.follow(me, recipient)

      # Send messages from both users
      {:ok, _op1} = Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _op2} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      conn
      |> visit("/messages?tab=followed_only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)
    end

    test "tab switching between All and Followed Only works correctly", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      unfollowed_user = fake_user!(account)

      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      {:ok, _follow} = Follows.follow(me, recipient)
      {:ok, _op1} = Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _op2} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      # Start with All tab - should see both messages
      session =
        conn
        |> visit("/messages?tab=all")
        |> assert_has_or_open_browser("#message_threads", text: followed_content)
        |> assert_has("#message_threads", text: unfollowed_content)

      # Switch to Followed Only tab - should see only followed user's message
      session
      |> click_link("Followed Only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)

      # Switch back to All tab - should see both messages again
      |> click_link("All")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> assert_has("#message_threads", text: unfollowed_content)
    end
  end

  describe "DM privacy settings integration" do
    test "DM privacy setting 'followed_only' makes Followed Only the default tab", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      # Set user's DM privacy to followed_only
      _updated_user =
        current_user(
          Bonfire.Common.Settings.put([Bonfire.Messages, :dm_privacy], "followed_only",
            current_user: me
          )
        )

      unfollowed_user = fake_user!(account)

      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      {:ok, _follow} = Follows.follow(me, recipient)
      {:ok, _op1} = Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _op2} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      # Visit messages without explicit tab parameter - should default to followed_only
      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)
    end

    test "explicit tab parameter overrides DM privacy setting", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      # Set user's DM privacy to followed_only
      _updated_user =
        current_user(
          Bonfire.Common.Settings.put([Bonfire.Messages, :dm_privacy], "followed_only",
            current_user: me
          )
        )

      unfollowed_user = fake_user!(account)

      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      {:ok, _follow} = Follows.follow(me, recipient)
      {:ok, _op1} = Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _op2} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      # Explicitly visit All tab - should override the followed_only setting
      conn
      |> visit("/messages?tab=all")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> assert_has("#message_threads", text: unfollowed_content)
    end
  end

  describe "tab state preservation" do
    test "tab context is preserved when navigating to individual thread", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      unfollowed_user = fake_user!(account)

      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      {:ok, _follow} = Follows.follow(me, recipient)

      {:ok, followed_op} =
        Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _unfollowed_op} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      # Start from Followed Only tab and click into a thread
      conn
      |> visit("/messages?tab=followed_only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> click_link(followed_content)
      |> assert_has_or_open_browser("article", text: followed_content)

      # Navigate back should return to Followed Only tab context
      conn
      |> visit("/messages?tab=followed_only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)
    end
  end
end
