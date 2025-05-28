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
    |> assert_has("#message_threads", text: content)
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
    IO.inspect(op, label: "Message Operation")
    # Create new connection as recipient
    recipient_conn = conn(user: recipient, account: account)

    recipient_conn
    |> visit("/messages")
    |> PhoenixTest.open_browser()
    |> assert_has("#message_threads", text: content)
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
    |> assert_has("article", text: content)
  end
end
