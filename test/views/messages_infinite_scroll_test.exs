defmodule Bonfire.UI.Messages.InfiniteScrollTest do
  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Messages

  setup do
    account = fake_account!()
    me = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me}
  end

  # Seed `count` separate DM threads (one recipient each) for `me`, so the
  # thread list spans more than one page. Each recipient gets a fresh account
  # to avoid the per-account profile cap.
  defp seed_threads(me, count) do
    for i <- 1..count do
      recipient = fake_user!()

      assert {:ok, _} =
               Messages.send(me, %{
                 to_circles: [recipient.id],
                 post_content: %{html_body: "test DM #{i}"}
               })
    end
  end

  describe "infinite scroll on the messages thread list" do
    test "the thread list paginates and the load_more control is wired for infinite scroll",
         %{conn: conn, me: me} do
      limit = Config.get(:default_pagination_limit, 8)
      # one more than a page, so a next-page cursor exists and the button renders
      seed_threads(me, limit + 1)

      conn
      |> visit("/messages")
      # only the first page is shown initially
      |> assert_has("[data-id=thread_participants]", count: limit)
      # The IntersectionObserver hook must be active (not the no-op "Ignore" hook).
      # Surface namespaces the hook name (e.g. "Bonfire.UI.Common.LoadMoreLive#LoadMore"),
      # so match the LoadMore suffix rather than the bare name.
      |> assert_has("[data-id=load_more][phx-hook*='LoadMore']")
      # the scroll event is what the hook pushes on intersection
      |> assert_has("[data-id=load_more][phx-scroll]")
      # ...and pointed at the #message_threads list, which LiveView resolves to the
      # owning MessagesLive view so the hook's `pushEventTo` reaches the view-level
      # load_more handler. Without this target the hook fires into the void and the
      # loading spinner hangs forever (the bug this guards against).
      |> assert_has("[data-id=load_more][phx-target='#message_threads']")
    end
  end
end
