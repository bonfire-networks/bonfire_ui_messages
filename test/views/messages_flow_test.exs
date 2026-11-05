defmodule Bonfire.UI.Messages.MessagesFlowTest do
  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Messages
  alias Bonfire.Social.Graph.Follows

  setup do
    account = fake_account!()
    me = fake_user!(account)
    recipient = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, recipient: recipient}
  end

  describe "thread view" do
    test "shows participant name in thread list", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "hello from thread view test"

      {:ok, _message} =
        Messages.send(me, %{post_content: %{html_body: content}}, recipient)

      recipient_name =
        e(recipient, :profile, :name, nil) || e(recipient, :character, :username, "")

      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("[data-id=thread_participants]", text: recipient_name)
    end

    test "displays message content preview in thread list", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "this is the message body in thread"

      {:ok, _message} =
        Messages.send(me, %{post_content: %{html_body: content}}, recipient)

      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: content)
    end
  end

  describe "new conversation flow" do
    test "new direct message button is visible on messages page", %{conn: conn} do
      conn
      |> visit("/messages")
      |> assert_has("button", text: "New Message")
    end

    test "clicking new direct message button opens contact picker", %{conn: conn} do
      conn
      |> visit("/messages")
      |> click_button("New Message")
      |> assert_has("h3", text: "New message")
    end

    test "visiting /messages/@username for a new contact stays on that URL", %{
      conn: conn,
      recipient: recipient
    } do
      username = e(recipient, :character, :username, "")

      # No existing thread -> no redirect; the DM composer opens via SmartInput portal.
      conn
      |> visit("/messages/@#{username}")
      |> assert_path("/messages/@#{username}")
    end
  end

  describe "username route" do
    test "visiting /messages/@username with existing thread redirects to thread", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "existing thread message"

      {:ok, message} =
        Messages.send(me, %{post_content: %{html_body: content}}, recipient)

      thread_id = e(message, :replied, :thread_id, nil) || id(message)
      username = e(recipient, :character, :username, "")

      # handle_params redirects to the thread's discussion
      conn
      |> visit("/messages/@#{username}")
      |> wait_async()
      |> assert_path("/discussion/#{thread_id}")
      |> assert_has_or_open_browser("[data-id=object_body]", text: content)
    end
  end

  # a message is read in its discussion, so every link to one, a push included, lands there
  describe "a message's own page" do
    test "a direct message's own path is its discussion page", %{me: me, recipient: recipient} do
      {:ok, op} = Messages.send(me, %{post_content: %{html_body: "the start of it"}}, recipient)

      {:ok, reply} =
        Messages.send(
          recipient,
          %{post_content: %{html_body: "the answer to it"}, reply_to_id: op.id},
          [me]
        )

      # already right before messages had a discussion path: a reply's place in its thread
      assert Bonfire.Social.Threads.permalink(reply) == "/discussion/#{op.id}/reply/1/#{reply.id}"

      assert Bonfire.Common.URIs.path(op) == "/discussion/#{op.id}"

      assert Bonfire.Social.Threads.permalink(op) == "/discussion/#{op.id}",
             "the link a push carries for the start of a thread"

      assert Bonfire.Common.URIs.path(reply) == "/discussion/#{reply.id}"
    end

    test "a participant opens a direct message from its push link", %{
      account: account,
      me: me,
      recipient: recipient
    } do
      {:ok, op} = Messages.send(me, %{post_content: %{html_body: "the start of it"}}, recipient)

      {:ok, reply} =
        Messages.send(
          recipient,
          %{post_content: %{html_body: "the answer to it"}, reply_to_id: op.id},
          [me]
        )

      conn(user: recipient, account: account)
      |> visit(Bonfire.Social.Threads.permalink(op))
      |> wait_async()
      |> assert_path("/discussion/#{op.id}")
      |> assert_has_or_open_browser("[data-id=object_body]", text: "the start of it")
      |> refute_has("h3", text: "Welcome to your inbox")

      # a reply's own page moves it to its place in the thread
      conn(user: me, account: account)
      |> visit(Bonfire.Common.URIs.path(reply))
      |> wait_async()
      |> assert_path("/discussion/#{op.id}/reply/1/#{reply.id}")
      |> assert_has_or_open_browser("[data-id=object_body]", text: "the start of it")
      |> assert_has("[data-id=object_body]", text: "the answer to it")
    end

    test "someone outside a direct message can't read it from its own page", %{
      me: me,
      recipient: recipient
    } do
      {:ok, op} =
        Messages.send(me, %{post_content: %{html_body: "between the two of us"}}, recipient)

      outsider_account = fake_account!()
      outsider = fake_user!(outsider_account)

      conn(user: outsider, account: outsider_account)
      |> visit("/discussion/#{op.id}")
      |> wait_async()
      |> assert_path("/discussion/#{op.id}")
      |> refute_has("[data-id=object_body]", text: "between the two of us")
      # TODO: PhoenixTest's HTML holds `#flash_error` with "Sorry, you can't view this message", but `assert_has` doesn't find it, possibly because unmatched close tags make the parser move the flash
      |> assert_has("h2", text: "Sorry, you cannot view this.")
    end
  end

  describe "thread search" do
    test "searching threads filters by participant name", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      other_user = fake_user!(account)

      # Send messages from two different users
      {:ok, _} =
        Messages.send(recipient, %{post_content: %{html_body: "message from recipient"}}, me)

      {:ok, _} =
        Messages.send(other_user, %{post_content: %{html_body: "message from other"}}, me)

      recipient_name =
        e(recipient, :profile, :name, nil) || e(recipient, :character, :username, "")

      conn
      |> visit("/messages")
      |> assert_has_or_open_browser("#message_threads", text: "message from recipient")
      |> assert_has("#message_threads", text: "message from other")
      |> fill_in("Search messages", with: recipient_name)
      |> assert_has_or_open_browser("#message_threads", text: "message from recipient")
      |> refute_has("#message_threads", text: "message from other")
    end
  end

  describe "not_followed tab" do
    @describetag skip:
                   "the Other tab was replaced by the Hidden tab, tested in create_message_test.exs"
    test "shows only messages from unfollowed users", %{
      conn: conn,
      me: me,
      recipient: recipient,
      account: account
    } do
      unfollowed_user = fake_user!(account)

      {:ok, _follow} = Follows.follow(me, recipient)

      {:ok, _} =
        Messages.send(recipient, %{post_content: %{html_body: "from followed"}}, me)

      {:ok, _} =
        Messages.send(unfollowed_user, %{post_content: %{html_body: "from unfollowed"}}, me)

      conn
      |> visit("/messages?tab=not_followed")
      |> assert_has_or_open_browser("#message_threads", text: "from unfollowed")
      |> refute_has("#message_threads", text: "from followed")
    end
  end
end
