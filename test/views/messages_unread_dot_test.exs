defmodule Bonfire.UI.Messages.MessagesUnreadDotTest do
  @moduledoc """
  Verifies that the unread-dot on a message-thread row in `/messages`
  disappears as soon as the receiver opens the thread, without needing a
  full page refresh.

  The wire is:
    * `<li>` carries `phx-hook=...PreviewActivity` (opens the modal)
    * AND `phx-click="Bonfire.Messages:mark_thread_seen"` (server flips
      `activity.seen` in `@threads.edges` + async-persists via Seen)

  Note on accounts: `Seen.mark_seen` normalises the subject to the user's
  account, so seen edges are per-account. Sender and receiver MUST live on
  separate accounts here, otherwise the sender's seen edge would also count
  for the receiver and the dot wouldn't appear in the first place.

  Note on visit-auto-mark: visiting `/messages` clears the inbox feed
  via `mark_feed_seen_on_visit` (see `messages_badge_reset_test.exs`), so
  by the time the page is rendered, all rows are seen and the per-row
  dot/phx-click wiring is gone. The per-row click handler is still load-
  bearing for messages that arrive in real-time *while* the user is on
  `/messages` (via the inbox PubSub subscription) — this test exercises
  the handler directly via `render_click` to verify the local-flip path,
  without depending on the initial DOM state.
  """

  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Messages

  setup do
    sender_account = fake_account!()
    sender = fake_user!(sender_account)

    receiver_account = fake_account!()
    receiver = fake_user!(receiver_account)

    {:ok, message} =
      Messages.send(
        sender,
        %{post_content: %{html_body: "say hi"}},
        receiver
      )

    conn = conn(user: receiver, account: receiver_account)
    thread_id = e(message, :replied, :thread_id, nil) || id(message)
    activity_id = id(message)

    {:ok,
     conn: conn,
     sender: sender,
     receiver: receiver,
     thread_id: thread_id,
     activity_id: activity_id}
  end

  test "the mark_thread_seen handler is a no-op for a stale activity_id (already seen / unknown)",
       %{conn: conn} do
    # Visiting /messages auto-marks everything seen, so by the time this
    # event fires there's nothing to flip. The handler must still return
    # cleanly. Regression guard: the helper short-circuits when the matched
    # edge already has seen set, returning the original threads reference.
    conn
    |> visit("/messages")
    |> wait_async()
    |> unwrap(fn view ->
      Phoenix.LiveViewTest.render_click(
        view,
        "Bonfire.Messages:mark_thread_seen",
        %{"activity_id" => "01ABCDEFGHJKMNPQRSTVWXYZ00"}
      )
    end)
  end

  test "live-arrival: a message that arrives via PubSub while on /messages shows the dot, and clicking the row clears it on the same connection",
       %{conn: conn, receiver: receiver} do
    # Reproduces the original user-reported bug end-to-end:
    #   1. user is on /messages (inbox is clean post-auto-clear)
    #   2. a NEW message arrives — `Bonfire.Social.LivePush.notify_of_message`
    #      broadcasts `{:new_message, ...}` on the receiver's inbox topic;
    #      MessagesLive's `handle_info` reloads threads
    #   3. the unread dot must appear for the new thread
    #   4. clicking the row fires `mark_thread_seen` and clears the dot
    #      *on the same connection* (no refresh)
    other_account = fake_account!()
    other_sender = fake_user!(other_account)

    session =
      conn
      |> visit("/messages")
      |> wait_async()

    {:ok, new_message} =
      Messages.send(
        other_sender,
        %{post_content: %{html_body: "fresh ping"}},
        receiver
      )

    new_tid = e(new_message, :replied, :thread_id, nil) || id(new_message)
    new_aid = id(new_message)

    session
    # force the LV to drain pending {:new_message, ...} info messages
    |> unwrap(fn view -> Phoenix.LiveViewTest.render(view) end)
    |> assert_has(~s|[data-id=unread_dot][data-thread-id="#{new_tid}"]|)
    |> unwrap(fn view ->
      Phoenix.LiveViewTest.render_click(
        view,
        "Bonfire.Messages:mark_thread_seen",
        %{"activity_id" => new_aid}
      )
    end)
    |> refute_has(~s|[data-id=unread_dot][data-thread-id="#{new_tid}"]|)
  end

  test "a row whose latest message was sent BY the viewer does NOT get the phx-click wiring", %{
    sender: sender,
    thread_id: tid
  } do
    # The setup sent one message from sender → receiver, so when the SENDER
    # views their own /messages, the latest message in this thread is their
    # own outbound one (subject_id == current_user_id). The unread-dot
    # condition is false → phx-click should not be rendered. (Independent
    # of visit-auto-mark, since `unread_for?` already excludes own outbound
    # rows.)
    sender_account = e(sender, :accounted, :account, nil) || e(sender, :account, nil)
    sender_conn = conn(user: sender, account: sender_account)

    sender_conn
    |> visit("/messages")
    |> refute_has(~s|li#thread-#{tid} div[phx-click="Bonfire.Messages:mark_thread_seen"]|)
    |> refute_has(~s|[data-id=unread_dot][data-thread-id="#{tid}"]|)
  end
end
