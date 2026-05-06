defmodule Bonfire.UI.Messages.MessagesBadgeResetTest do
  @moduledoc """
  Verifies that visiting `/messages` automatically marks every unseen
  activity in the receiver's inbox feed as seen — same effect as clicking
  the "Mark all as read" button on the page header.
  """

  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Messages
  alias Bonfire.Social.FeedActivities

  setup do
    sender_account = fake_account!()
    sender = fake_user!(sender_account)

    receiver_account = fake_account!()
    receiver = fake_user!(receiver_account)

    {:ok, _message} =
      Messages.send(
        sender,
        %{post_content: %{html_body: "ping"}},
        receiver
      )

    conn = conn(user: receiver, account: receiver_account)
    {:ok, conn: conn, sender: sender, receiver: receiver}
  end

  test "visiting /messages clears the inbox unseen count", %{conn: conn, receiver: receiver} do
    assert FeedActivities.unseen_count(:inbox, current_user: receiver) > 0,
           "test premise broken: expected receiver to have unseen inbox items"

    conn
    |> visit("/messages")
    |> wait_async()

    assert FeedActivities.unseen_count(:inbox, current_user: receiver) == 0,
           "expected /messages to mark all inbox items as seen on visit"
  end

  test "visiting /messages drops the inbox badge indicator from the rendered DOM", %{
    conn: conn,
    receiver: receiver
  } do
    # Beyond the data-layer assertion above: verify the user-visible badge.
    # The `BadgeCounterLive` component always renders `[data-id=unseen_count]`
    # but only renders an `.indicator-item` div inside when `count > 0`.
    inbox_id = e(receiver, :character, :inbox_id, nil)
    refute is_nil(inbox_id), "test premise broken: receiver has no inbox_id"

    conn
    |> visit("/messages")
    |> wait_async()
    |> refute_has(~s|#unseen_count_#{inbox_id} .indicator-item|)
  end
end
