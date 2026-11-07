defmodule Bonfire.UI.Messages.MessagesBlockKeywordsTest do
  @moduledoc """
  A direct message matching one of its recipient's filtered keywords shows to them as "[Content blocked by filters]", in the conversation and in the list of conversations. Its sender, who has no such keyword, sees the text.
  """
  use Bonfire.UI.Messages.ConnCase, async: false
  use Bonfire.Common.Utils

  alias Bonfire.Messages
  alias Bonfire.Boundaries.BlockKeywords

  @moduletag :ui

  @placeholder "[Content blocked by filters]"

  setup do
    sender_account = fake_account!()
    sender = fake_user!(sender_account)

    recipient_account = fake_account!()
    recipient = fake_user!(recipient_account)
    {:ok, _} = BlockKeywords.put_block_keywords_settings(["viagra"], current_user: recipient)

    {:ok, op} =
      Messages.send(sender, %{post_content: %{html_body: "Cheap viagra for you"}}, recipient)

    {:ok,
     op: op,
     sender: conn(user: sender, account: sender_account),
     recipient: conn(user: recipient, account: recipient_account)}
  end

  test "in the conversation, a matching message shows the placeholder to its recipient", %{
    op: op,
    sender: sender,
    recipient: recipient
  } do
    sender
    |> visit("/discussion/#{op.id}")
    |> wait_async()
    |> assert_has("[data-id=object_body]", text: "Cheap viagra for you")

    recipient
    |> visit("/discussion/#{op.id}")
    |> wait_async()
    |> assert_has("#thread_main_object", text: @placeholder)
    |> refute_has("body", text: "Cheap viagra for you")
  end

  test "in the list of conversations, a matching message's preview shows the placeholder to its recipient",
       %{sender: sender, recipient: recipient} do
    sender
    |> visit("/messages")
    |> wait_async()
    |> assert_has("#message_threads", text: "Cheap viagra for you")

    recipient
    |> visit("/messages")
    |> wait_async()
    |> assert_has("#message_threads", text: @placeholder)
    |> refute_has("body", text: "Cheap viagra for you")
  end
end
