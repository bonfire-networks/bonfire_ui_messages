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
    test "shows participant name in thread header", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "hello from thread view test"

      {:ok, message} =
        Messages.send(me, %{post_content: %{html_body: content}}, recipient)

      thread_id = e(message, :replied, :thread_id, nil) || id(message)

      recipient_name =
        e(recipient, :profile, :name, nil) || e(recipient, :character, :username, "")

      conn
      |> visit("/messages/#{thread_id}")
      |> assert_has_or_open_browser("h3", text: recipient_name)
    end

    test "displays message content in thread", %{
      conn: conn,
      me: me,
      recipient: recipient
    } do
      content = "this is the message body in thread"

      {:ok, message} =
        Messages.send(me, %{post_content: %{html_body: content}}, recipient)

      thread_id = e(message, :replied, :thread_id, nil) || id(message)

      conn
      |> visit("/messages/#{thread_id}")
      |> assert_has_or_open_browser("article", text: content)
    end
  end

  describe "new conversation flow" do
    test "new direct message button is visible on messages page", %{conn: conn} do
      conn
      |> visit("/messages")
      |> assert_has("button", text: "New direct message")
    end

    test "visiting /messages/@username for a new contact shows new conversation", %{
      conn: conn,
      recipient: recipient
    } do
      username = e(recipient, :character, :username, "")

      recipient_name =
        e(recipient, :profile, :name, nil) || e(recipient, :character, :username, "")

      # The username route should show the new conversation view
      conn
      |> visit("/messages/@#{username}")
      |> assert_has("h3", text: recipient_name)
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

      # push_patch from handle_params redirects to the thread URL
      conn
      |> visit("/messages/@#{username}")
      |> assert_path("/messages/#{thread_id}")
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
