defmodule Bonfire.UI.Messages.ContactPickerLive do
  use Bonfire.UI.Common.Web, :stateful_component

  prop selected_recipients, :list, default: []

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       search_results: [],
       search_text: "",
       suggested_users: nil
     )}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if is_nil(socket.assigns[:suggested_users]) do
        load_suggested_users(socket)
      else
        socket
      end

    {:ok, socket}
  end

  defp load_suggested_users(socket) do
    current_user = current_user(socket)

    suggested =
      if current_user do
        Bonfire.Social.Graph.Follows.list_my_followed(current_user,
          paginate: false,
          type: Bonfire.Data.Identity.User,
          limit: 30
        )
        |> Enum.map(&e(&1, :edge, :object, nil))
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    assign(socket, suggested_users: suggested)
  end

  def display_contacts(search_text, search_results, suggested_users) do
    if String.length(search_text || "") >= 2 do
      {search_results, l("Results"), l("No people found")}
    else
      {suggested_users || [], l("Suggested"), l("Search for people to start a conversation")}
    end
  end

  def handle_event("search_contacts", %{"search" => text}, socket) do
    text = String.trim(text)

    results =
      if String.length(text) >= 2 do
        Bonfire.Me.Users.search(text)
        |> Enum.map(fn
          %Needle.Pointer{activity: %{object: user}} -> user
          other -> other
        end)
      else
        []
      end

    {:noreply, assign(socket, search_results: results, search_text: text)}
  end
end
