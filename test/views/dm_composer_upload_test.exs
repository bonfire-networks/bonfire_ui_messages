defmodule Bonfire.UI.Messages.DmComposerUploadTest do
  @moduledoc """
  The composer's upload button in each state a direct message puts it in. A message carries the files uploaded with it, as a post does (attached, or placed in its text), so the button works while the composer writes one, and still works when it writes a post again.

  The composer lives in the sticky `PersistentLive` child LV, so interactions go through `find_live_child(view, "persistent")` rather than PhoenixTest.
  """
  use Bonfire.UI.Messages.ConnCase, async: false
  use Bonfire.Common.Utils
  import Phoenix.LiveViewTest

  alias Bonfire.Messages

  @moduletag :ui

  @upload_input "#smart_input_form input[name=files][type=file]"
  @message_type "#smart_input_form input[name=create_object_type][value=message]"

  setup do
    account = fake_account!()
    me = fake_user!(account)
    recipient = fake_user!(account)

    conn = conn(user: me, account: account)
    image = Path.expand("../fixtures/icon.png", __DIR__)

    {:ok, conn: conn, me: me, recipient: recipient, image: image}
  end

  defp composer(conn, path) do
    {:ok, view, _html} = live(conn, path)
    persistent = find_live_child(view, "persistent")
    assert persistent, "sticky PersistentLive child not found"

    # the page opens the composer by messaging the sticky child: rendering both makes sure it was handled
    render(view)
    render(persistent)
    {view, persistent}
  end

  # as a person does: New Message, pick the recipient in the contact picker, start
  defp dm_composer(conn, recipient) do
    {view, persistent} = composer(conn, "/messages")

    render_hook(view, "Bonfire.Messages:toggle_contact_picker", %{})

    render_hook(view, "Bonfire.Messages:toggle_recipient", %{
      "id" => id(recipient),
      "name" => e(recipient, :profile, :name, "")
    })

    render_hook(view, "Bonfire.Messages:start_direct_message", %{})
    render(persistent)

    assert has_element?(persistent, @message_type), "control: the composer writes a message"
    {view, persistent}
  end

  defp upload_image!(persistent, image) do
    persistent
    |> file_input("#smart_input_form", :files, [
      %{name: "icon.png", content: File.read!(image), type: "image/png"}
    ])
    |> render_upload("icon.png")

    assert has_element?(persistent, ".uploads_preview"), "the chosen image isn't in the composer"
  end

  test "control: the post composer on the feed has a working upload button", %{
    conn: conn,
    image: image
  } do
    {_view, persistent} = composer(conn, "/feed/local")

    assert has_element?(persistent, @upload_input)
    upload_image!(persistent, image)
  end

  test "a new direct message has a working upload button", %{
    conn: conn,
    recipient: recipient,
    image: image
  } do
    {_view, persistent} = dm_composer(conn, recipient)

    assert has_element?(persistent, @upload_input)
    upload_image!(persistent, image)
  end

  # the composer writes `upload:<ref>` for a file it hasn't uploaded yet: sending stores the file, attaches it, and puts its URL there
  test "a direct message sent with an image placed in its text has it attached, at its stored URL",
       %{conn: conn, me: me, recipient: recipient, image: image} do
    {_view, persistent} = dm_composer(conn, recipient)
    upload_image!(persistent, image)

    [_, ref] = Regex.run(~r/upload_metadata\[([^\]]+)\]/, render(persistent))

    persistent
    |> element("#smart_input_form")
    |> render_submit(%{
      "create_object_type" => "message",
      "to_circles" => [recipient.id],
      "post" => %{"post_content" => %{"html_body" => "Intro\n\n![](upload:#{ref})\n\nmore"}}
    })

    assert %{edges: [message | _]} = Messages.list(me, id(recipient), limit: 1)

    message =
      (e(message, :activity, :object, nil) || e(message, :object, nil) || message)
      |> Bonfire.Common.Repo.maybe_preload([:post_content, files: [:media]], force: true)

    assert [%{media: media}] = message.files
    body = e(message, :post_content, :html_body, nil)
    refute body =~ "upload:"
    assert Bonfire.Files.InlineMedia.inline_ids(body, [media]) == [id(media)]
  end

  test "replying in a direct message has a working upload button", %{
    conn: conn,
    me: me,
    recipient: recipient,
    image: image
  } do
    {:ok, op} = Messages.send(recipient, %{post_content: %{html_body: "a private hello"}}, me)

    {view, persistent} = composer(conn, "/discussion/#{op.id}")
    render_hook(view, "Bonfire.Social.Feeds:reply_to_activity", %{"id" => op.id})
    render(persistent)

    assert has_element?(persistent, @message_type), "control: the composer writes a message"
    assert has_element?(persistent, @upload_input)
    upload_image!(persistent, image)
  end

  # Mentaal: "I cannot add images to posts anymore. Even not to new posts: the button doesn't work"
  test "after sending a direct message, the composer's upload button works for a post again", %{
    conn: conn,
    me: me,
    recipient: recipient,
    image: image
  } do
    {_view, persistent} = dm_composer(conn, recipient)

    persistent
    |> element("#smart_input_form")
    |> render_submit(%{
      "create_object_type" => "message",
      "to_circles" => [recipient.id],
      "post" => %{"post_content" => %{"html_body" => "a private hello"}}
    })

    render(persistent)

    assert %{edges: [_ | _]} = Messages.list(me, id(recipient), limit: 1),
           "control: the message was sent"

    refute has_element?(persistent, @message_type)
    assert has_element?(persistent, @upload_input)
    upload_image!(persistent, image)
  end
end
