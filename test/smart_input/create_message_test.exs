defmodule Bonfire.UI.Messages.CreateMessageTest do
  use Bonfire.UI.Messages.ConnCase, async: true
  use Bonfire.Common.Utils
  import Bonfire.Files.Simulation

  alias Bonfire.Social.Fake
  alias Bonfire.Messages
  alias Bonfire.Social.Graph.Follows
  alias Bonfire.Files.Test

  describe "send a message" do
    test "shows a confirmation flash" do
      some_account = fake_account!()
      someone = fake_user!(some_account)
      recipient = fake_user!()

      content = "here is an epic html message"

      conn = conn(user: someone, account: some_account)

      next = "/settings"
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)

      # wait for persistent smart input to be ready
      live_async_wait(view)

      assert sent =
               view
               |> form("#smart_input form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(recipient)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      # |> Floki.text() =~ "sent"

      live_async_wait(view)
      # assert [ok] = find_flash(sent)
      assert has_element?(view, "[role=alert]", "Sent!")
    end

    test "shows up in sender's message threads list" do
      some_account = fake_account!()
      someone = fake_user!(some_account)
      recipient = fake_user!()

      content = "here is an epic html message"

      conn = conn(user: someone, account: some_account)

      next = "/settings"
      # |> IO.inspect
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      live_async_wait(view)

      assert sent =
               view
               |> form("#smart_input form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(recipient)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      next = "/messages"
      # |> IO.inspect
      {:ok, profile, _html} = live(conn, next)
      assert has_element?(profile, "#message_threads", content)
    end

    test "shows up in recipients's message threads list" do
      some_account = fake_account!()
      someone = fake_user!(some_account)
      recipient = fake_user!()

      content = "here is an epic html message"

      conn = conn(user: someone, account: some_account)

      next = "/settings"
      # |> IO.inspect
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      live_async_wait(view)

      assert sent =
               view
               |> form("#smart_input form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(recipient)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      conn = conn(user: recipient)

      next = "/messages"
      # |> IO.inspect
      {:ok, profile, _html} = live(conn, next)
      assert has_element?(profile, "#message_threads", content)
    end

    test "does not show up on my profile timeline" do
      some_account = fake_account!()
      someone = fake_user!(some_account)
      recipient = fake_user!()

      content = "here is an epic html message"

      conn = conn(user: someone, account: some_account)

      next = "/settings"
      # |> IO.inspect
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      live_async_wait(view)

      assert sent =
               view
               |> form("#smart_input form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(recipient)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      next = "/user"
      # |> IO.inspect
      {:ok, profile, _html} = live(conn, next)
      refute has_element?(profile, "[data-id=feed]", content)
    end

    test "recipient can send reply, which appears instantly on thread page" do
      alice = fake_user!("none")
      recipient = fake_user!()

      attrs = %{
        post_content: %{
          summary: "summary",
          name: "test message name",
          html_body: "first message"
        }
      }

      assert {:ok, op} =
               Messages.send(alice, attrs, recipient)

      content = "epic reply"

      conn = conn(user: recipient)

      next = "/messages/#{id(op)}"
      # |> IO.inspect
      {:ok, view, _html} = live(conn, next)
      live_async_wait(view)

      # open_browser(view)

      assert _click =
               view
               |> element("[data-id=action_reply]")
               |> render_click()

      assert sent =
               view
               |> form("#smart_input form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(alice)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      # assert [ok] = find_flash(sent)
      # assert ok |> Floki.text() =~ "Sent"
      has_element?(view, "[role=alert]", "Sent!")

      conn2 = conn(user: alice)

      # next = "/@#{bob.character.username}"
      # |> IO.inspect
      {:ok, feed, _html} = live(conn2, next)
      live_async_wait(view)
      open_browser(view)

      assert has_element?(feed, "[data-role=thread]", content)
    end

    # fix first in `Bonfire.UI.Posts`
    # @tag :todo
    test "with uploads" do
      # Create alice user
      account = fake_account!()
      alice = fake_user!(account)
      recipient = fake_user!()

      # login as alice
      conn = conn(user: alice, account: account)
      {:ok, view, _html} = live(conn, "/write")

      file = Path.expand("../fixtures/icon.png", __DIR__)
      # open_browser(view)

      icon =
        file_input(view, "#smart_input_form", :files, [
          %{
            name: "image.png",
            content: File.read!(file),
            type: "image/png"
          }
        ])

      uploaded = render_upload(icon, "image.png")

      # create a post
      content = "here is an epic html message"

      assert sent =
               view
               |> form("#smart_input_form")
               |> render_submit(%{
                 "create_object_type" => "message",
                 "to_circles" => [id(recipient)],
                 "post" => %{"post_content" => %{"html_body" => content}}
               })

      assert [ok] = find_flash(sent)
      {:ok, refreshed_view, _html} = live(conn, "/feed/local")
      # open_browser(refreshed_view)
    end
  end
end
