defmodule Bonfire.UI.Messages.CreateMessageTest do
  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
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

    attrs = %{
      post_content: %{
        html_body: content
      }
    }

    {:ok, _message} = Messages.send(me, attrs, recipient)

    conn
    |> visit("/user")
    |> refute_has("[data-id=feed]", text: content)
  end

  test "reply to a thread appears in the inbox thread list", %{
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

    assert {:ok, _re} =
             Messages.send(me, reply, recipient)

    # Thread content is now shown via preview modal; the thread list previews the latest reply
    conn
    |> visit("/messages")
    |> assert_has_or_open_browser("#message_threads", text: content)
  end

  # the "All" / "Followed only" / "Other" tabs and the `dm_privacy` setting were replaced by the "Hide notifications and messages from" switches, with a Inbox tab and a Hidden tab: the same cases are tested in "Inbox and Hidden tabs" below
  describe "Inbox and Hidden tabs" do
    setup %{me: me, recipient: friend, account: account} do
      stranger = fake_user!(account)
      {:ok, _follow} = Follows.follow(me, friend)

      {:ok, _} = Messages.send(friend, %{post_content: %{html_body: "message from a friend"}}, me)

      {:ok, _} =
        Messages.send(stranger, %{post_content: %{html_body: "message from a stranger"}}, me)

      :ok
    end

    defp hiding_strangers(me, account) do
      me =
        current_user(
          Bonfire.Common.Settings.put(
            Bonfire.Social.Notifications.audience_key(:not_followed),
            :hide,
            current_user: me
          )
        )

      conn(user: me, account: account)
    end

    test "with nothing hidden, Inbox has every conversation and there is no Hidden tab", %{
      conn: conn
    } do
      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: "message from a friend")
      |> assert_has("#message_threads", text: "message from a stranger")
      |> assert_has("#messages-tab-inbox")
      |> refute_has("#messages-tab-hidden")
    end

    test "with people you don't follow hidden, Inbox leaves out a stranger and Hidden has only them",
         %{me: me, account: account} do
      conn = hiding_strangers(me, account)

      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: "message from a friend")
      |> refute_has("#message_threads", text: "message from a stranger")

      conn
      |> visit("/messages?tab=hidden")
      |> assert_has_or_open_browser("#message_threads", text: "message from a stranger")
      |> refute_has("#message_threads", text: "message from a friend")
    end

    # as the notifications Hidden chip: a view someone isn't offered lands on the normal one, rather than a page that would always be empty
    test "with nothing hidden, the hidden tab's URL shows Inbox, and no Hidden tab", %{conn: conn} do
      conn
      |> visit("/messages?tab=hidden")
      |> assert_has("#messages-tab-inbox[aria-current=page]")
      |> refute_has("#messages-tab-hidden")
      |> assert_has_or_open_browser("#message_threads", text: "message from a friend")
      |> assert_has("#message_threads", text: "message from a stranger")
    end

    test "flipping a switch in the panel brings the Hidden tab, and flipping it back takes it away",
         %{conn: conn} do
      name = Bonfire.Social.Notifications.audiences()[:not_followed][:name]

      conn
      |> visit("/messages")
      |> refute_has("#messages-tab-hidden")
      |> within("#messages-audiences-panel", fn session ->
        check(session, "#notification-audience-not_followed", name)
      end)
      |> assert_has("#messages-tab-hidden")
      |> within("#messages-audiences-panel", fn session ->
        uncheck(session, "#notification-audience-not_followed", name)
      end)
      |> refute_has("#messages-tab-hidden")
    end

    test "the preferences button beside the tabs holds the same switches as notifications", %{
      conn: conn
    } do
      conn
      |> visit("/messages")
      |> assert_has("#messages-audiences-toggle[aria-controls=messages-audiences-panel]")
      |> assert_has("#messages-audiences-panel #notification-audience-not_followed")
    end

    test "clicking between Inbox and Hidden switches the list", %{me: me, account: account} do
      hiding_strangers(me, account)
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: "message from a friend")
      |> click_link("#messages-tab-hidden", "Hidden")
      |> assert_has_or_open_browser("#message_threads", text: "message from a stranger")
      |> refute_has("#message_threads", text: "message from a friend")
      |> click_link("#messages-tab-inbox", "Inbox")
      |> assert_has_or_open_browser("#message_threads", text: "message from a friend")
      |> refute_has("#message_threads", text: "message from a stranger")
    end
  end

  describe "DM filtering tabs (replaced, see above)" do
    @describetag skip: "replaced by the Inbox and Hidden tabs"
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
      |> click_link("Followed only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)

      # Switch back to All tab - should see both messages again.
      # Scoped by href because `click_link/2` matches text as a SUBSTRING, and the nav's "All groups" link matches "All" just as well as the tab does.
      |> click_link("a[href='/messages?tab=all']", "All")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> assert_has("#message_threads", text: unfollowed_content)
    end
  end

  describe "DM privacy settings integration (replaced, see Inbox and Hidden tabs)" do
    @describetag skip: "`dm_privacy` was replaced by the audience switches"
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

  describe "tab state preservation (replaced, see Inbox and Hidden tabs)" do
    @describetag skip: "the Followed only tab was replaced by the Hidden tab"
    test "followed_only tab filter persists across visits", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      unfollowed_user = fake_user!(account)

      followed_content = "message from followed user"
      unfollowed_content = "message from unfollowed user"

      {:ok, _follow} = Follows.follow(me, recipient)

      {:ok, _followed_op} =
        Messages.send(recipient, %{post_content: %{html_body: followed_content}}, me)

      {:ok, _unfollowed_op} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: unfollowed_content}}, me)

      # Thread preview is now a JS-driven modal so we don't navigate off the inbox —
      # verify the URL-based tab filter keeps working on revisits.
      conn
      |> visit("/messages?tab=followed_only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)

      conn
      |> visit("/messages?tab=followed_only")
      |> assert_has_or_open_browser("#message_threads", text: followed_content)
      |> refute_has("#message_threads", text: unfollowed_content)
    end
  end
end
