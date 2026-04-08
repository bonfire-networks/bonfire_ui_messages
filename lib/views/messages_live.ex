defmodule Bonfire.UI.Messages.MessagesLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  alias Bonfire.Messages.LiveHandler
  import Untangle

  declare_extension("UI for messages",
    icon: "ph:tray-duotone",
    emoji: "✉️",
    description: l("User interface for writing and reading private messages.")
  )

  declare_nav_link(l("Direct Messages"),
    icon: "ph:tray-duotone",
    page: "messages",
    badge: [
      id: :inbox,
      feed_key: :inbox_id
    ]
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.UserRequired]}

  def mount(params, _session, socket) do
    feed_id = :inbox
    current_user = current_user_required!(socket)

    filter_tab = determine_filter_tab(params, current_user)

    threads =
      ed(assigns(socket), :threads, nil) ||
        LiveHandler.list_threads(current_user, socket, tab: filter_tab)

    # Subscribe to inbox updates
    if current_user do
      user_inbox_id =
        Bonfire.Social.Feeds.my_feed_id(:inbox, current_user)

      if user_inbox_id, do: PubSub.subscribe(user_inbox_id, socket)
    end

    {
      :ok,
      socket
      |> assign(
        showing_within: :messages,
        back: true,
        threads: threads,
        page_title: l("Messages"),
        page: "messages",
        no_index: true,
        feed_id: feed_id,
        thread_id: nil,
        thread_mode: maybe_to_atom(e(params, "mode", nil)),
        feedback_title: l("No messages"),
        feedback_message: l("Select a thread or start a new one..."),
        selected_tab: "messages",
        filter_tab: filter_tab,
        search_term: nil,
        composing_new: false,
        selected_recipients: [],
        page_header_aside: [
          {Bonfire.UI.Messages.HeaderAsideDmLive,
           [feed_id: e(current_user, :character, :inbox_id, nil) || feed_id]}
        ]
      )
    }
  end

  def handle_params(%{"username" => username} = params, _url, socket) do
    current_user = current_user_required!(socket)
    current_username = e(current_user, :character, :username, nil)
    filter_tab = determine_filter_tab(params, current_user)

    user =
      case username do
        nil ->
          current_user

        username when username == current_username ->
          current_user

        username ->
          with {:ok, user} <- Bonfire.Me.Users.by_username(username) do
            user
          else
            _ -> nil
          end
      end

    if user do
      # Check if a DM thread already exists with this user
      existing =
        if id(user) != id(current_user) do
          Bonfire.Messages.list(current_user, id(user),
            latest_in_threads: true,
            limit: 1
          )
        end

      case e(existing, :edges, []) do
        [%{activity: activity} | _] ->
          # Found existing thread - redirect to it
          thread_id = e(activity, :replied, :thread_id, nil) || id(e(activity, :object, nil))

          {:noreply,
           socket
           |> push_patch(to: "/messages/#{thread_id}")}

        _ ->
          # No existing thread - open composer via SmartInput
          user_circle = [{id(user), e(user, :character, :username, "")}]
          LiveHandler.open_dm_composer(user_circle, socket)

          {:noreply,
           socket
           |> assign(
             page: "messages",
             page_title:
               e(user, :profile, :name, nil) || e(user, :character, :username, l("Messages")),
             filter_tab: filter_tab,
             composing_new: false,
             page_header_aside: []
           )}
      end
    else
      {:noreply,
       socket
       |> assign_flash(:error, l("User %{username} not found", username: username))
       |> redirect_to(path(:error, :not_found))}
    end
  end

  def handle_params(%{"id" => id} = params, url, socket) do
    if not is_uid?(id) do
      # Strip leading @ since /messages/@:username route may match :id first
      username = String.trim_leading(id, "@")
      handle_params(%{"username" => username}, url, socket)
    else
      current_user = current_user_required!(socket)
      filter_tab = determine_filter_tab(params, current_user)

      {:noreply,
       socket
       |> assign(
         thread_id: id,
         filter_tab: filter_tab,
         page: "messages",
         page_header_aside: []
       )}
    end
  end

  # show all my threads
  def handle_params(params, _url, socket) do
    current_user = current_user_required!(socket)

    filter_tab = determine_filter_tab(params, current_user)

    # Always reload threads when tab changes
    threads = LiveHandler.list_threads(current_user, socket, tab: filter_tab)

    {
      :noreply,
      socket
      |> assign(
        threads: threads,
        page_title: l("Direct Messages"),
        filter_tab: filter_tab,
        composing_new: false,
        thread_id: nil
      )
    }
  end

  # Helper function to determine filter tab based on params and user settings
  defp determine_filter_tab(params, current_user) do
    case params["tab"] do
      nil ->
        dm_privacy =
          Bonfire.Common.Settings.get([Bonfire.Messages, :dm_privacy], "everyone",
            current_user: current_user
          )

        case to_string(dm_privacy) do
          "followed_only" -> "followed_only"
          _ -> "all"
        end

      "all" ->
        "all"

      "followed_only" ->
        "followed_only"

      explicit_tab ->
        explicit_tab
    end
  end

  def handle_event("remove", %{data: %{"field" => field, "id" => id}}, socket) do
    {:noreply,
     socket
     |> update(maybe_to_atom(field), fn current_to_circles ->
       List.wrap(current_to_circles) -- [{id}]
     end)}
  end

  # Handle PubSub messages for new messages
  def handle_info({:new_message, _}, socket) do
    current_user = current_user_required!(socket)

    # TODO: just add the new thread instead? but need to handle cases where it's a reply to an existing thread
    threads = LiveHandler.list_threads(current_user, socket)

    {:noreply,
     socket
     |> assign(threads: threads)}
  end

  # Handle other PubSub messages
  def handle_info(message, socket) do
    debug(message, "unhandled")
    {:noreply, socket}
  end
end
