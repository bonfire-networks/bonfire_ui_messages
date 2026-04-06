defmodule Bonfire.UI.Messages.MessagesLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  # alias Bonfire.Social
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
    # feed_id = Bonfire.Social.Feeds.my_feed_id(feed_id, socket)
    current_user = current_user_required!(socket)

    # Determine filter tab based on params and user's DM privacy setting
    filter_tab = determine_filter_tab(params, current_user)

    threads =
      ed(assigns(socket), :threads, nil) ||
        LiveHandler.list_threads(current_user, socket, tab: filter_tab)

    # |> debug("list_threads")

    # Subscribe to inbox updates
    if current_user do
      # Subscribe to a general inbox feed?
      # PubSub.subscribe(:inbox, socket)

      # Subscribe to user's specific inbox feed
      user_inbox_id =
        Bonfire.Social.Feeds.my_feed_id(:inbox, current_user)

      # |> debug("user_inbox_id")

      if user_inbox_id, do: PubSub.subscribe(user_inbox_id, socket)
      # |> debug("subscribed")
    end

    {
      :ok,
      socket
      |> assign(
        showing_within: :messages,
        back: true,
        threads: threads,
        thread_active: false,
        #  smart_input_opts: %{prompt: l("Message"), icon: "mdi:inbox"},
        #  smart_input_opts: [inline_only: true],
        # to_boundaries: [{"message", "Message"}],
        without_secondary_widgets: true,
        page_title: l("Messages"),
        page: "messages",
        no_index: true,
        feed_id: feed_id,
        activity: nil,
        object: nil,
        include_path_ids: nil,
        tab_id: nil,
        #  reply_to_id: nil,
        thread_id: nil,
        no_header: true,
        thread_mode: maybe_to_atom(e(params, "mode", nil)),
        feedback_title: l("No messages"),
        feedback_message: l("Select a thread or start a new one..."),
        selected_tab: "messages",
        filter_tab: filter_tab,
        search_term: nil,
        composing_new: false,
        selected_recipients: [],
        compose_user: nil,
        participants: [],
        participants_names: nil,
        reply_id: nil,
        url: nil,
        context_id: nil,
        page_header_aside: [
          {Bonfire.UI.Messages.HeaderAsideDmLive, [feed_id: feed_id]}
        ]
        #  sidebar_widgets: [
        #    users: [
        #      secondary: [
        #        {Bonfire.Tag.Web.WidgetTagsLive, []}
        #      ]
        #    ]
        #  ]

        #  nav_items: []
      )
      #  |> assign_global(ui_compact: true)
    }
  end

  def handle_params(%{"username" => username} = params, _url, socket) do
    # view messages excanged with a particular user

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
            _ ->
              nil
          end
      end

    # debug(user: user)

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
          # No existing thread - show new conversation view and open portal SmartInput
          user_circle = [{id(user), e(user, :character, :username, "")}]
          LiveHandler.open_dm_composer(user_circle, socket)

          {:noreply,
           socket
           |> assign(
             page: "messages",
             tab_id: "new_conversation",
             page_title:
               e(user, :profile, :name, nil) || e(user, :character, :username, l("Messages")),
             filter_tab: filter_tab,
             compose_user: user,
             composing_new: false,
             thread_active: true,
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

  # def handle_params(%{"id" => "compose" = id} = params, url, socket) do
  #   current_user = current_user_required!(socket)
  #   users = Bonfire.Social.Graph.Follows.list_my_followed(current_user, paginate: false)

  #   {:noreply,
  #    socket
  #    |> assign(
  #      page_title: l("Direct Messages"),
  #      page: "messages",
  #      users: users,
  #      tab_id: "select_recipients",
  #      reply_to_id: nil,
  #      thread_id: nil,
  #      to_circles: []
  #      #  sidebar_widgets:
  #      #    LiveHandler.threads_widget(current_user, uid(e(assigns(socket), :user, nil)),
  #      #      thread_id: nil,
  #      #      tab_id: "select_recipients"
  #      #    )
  #    )}
  # end

  def handle_params(%{"id" => id} = params, url, socket) do
    if not is_uid?(id) do
      # Strip leading @ since /messages/@:username route may match :id first
      username = String.trim_leading(id, "@")
      handle_params(%{"username" => username}, url, socket)
    else
      # show a message thread

      current_user = current_user_required!(socket)
      filter_tab = determine_filter_tab(params, current_user)

      # Bonfire.Social.Objects.LiveHandler.default_preloads()
      preloads = [
        # :default,
        :with_creator,
        :with_post_content,
        # :with_reply_to,
        :with_thread_name,
        :with_parent,
        :with_media,
        :maybe_with_labelled,
        # :tags,
        :with_object_peered
      ]

      # socket = socket |> assign(thread_active: true)
      with {:ok, message} <-
             Bonfire.Messages.read(id, current_user: current_user, preload: preloads) do
        # debug(message, "the first message in thread")

        # message =
        #   Bonfire.Social.Activities.activity_preloads(message, preloads, current_user: current_user)
        # |> debug("preloaded")

        # TODO: clean up the following
        {activity, message} = Map.pop(message, :activity)
        # {preloaded_object, activity} = Map.pop(activity, :object)
        # message = Map.merge(message, preloaded_object)

        reply_id = e(params, "reply_id", nil)
        thread_id = e(activity, :replied, :thread_id, nil) || id

        # debug(activity, "activity")
        # smart_input_prompt =
        #   l("Reply to message:") <>
        #     " " <>
        #     Text.text_only(
        #       e(
        #         message,
        #         :post_content,
        #         :name,
        #         e(
        #           message,
        #           :post_content,
        #           :summary,
        #           e(message, :post_content, :html_body, reply_id)
        #         )
        #       )
        #     )

        %{
          participants: participants,
          names: participants_names,
          title: title
        } = LiveHandler.thread_meta(thread_id, activity, message, current_user: current_user)

        #  |> debug("thread_meta")

        {
          :noreply,
          socket
          |> assign(
            page_title: e(activity, :replied, :thread, :named, :name, nil) || title,
            page: "messages",
            tab_id: "thread",
            reply_id: reply_id,
            # reply_to_id: thread_id,
            url: url,
            back: true,
            thread_active: true,
            activity: activity,
            object: message,
            context_id: thread_id,
            thread_id: thread_id,
            include_path_ids:
              Bonfire.Social.Threads.LiveHandler.maybe_include_path_ids(
                reply_id,
                e(params, "level", nil),
                e(assigns(socket), :__context__, nil) || assigns(socket)
              ),
            participants: participants,
            participants_names: participants_names,
            filter_tab: filter_tab,
            # to_circles: to_circles || [],
            page_header_aside: [],
            sidebar_widgets: [
              users: [
                main: [
                  # {Bonfire.UI.Messages.MessageThreadsLive,
                  #  [
                  #    context: nil,
                  #    tab_id: nil,
                  #    showing_within: :messages,
                  #    threads: e(assigns(socket), :threads, nil) || LiveHandler.list_threads(current_user, socket)
                  #  ]}
                ]
              ]
            ]
            # sidebar_widgets:
            #   LiveHandler.threads_widget(current_user, uid(e(assigns(socket), :user, nil)),
            #     thread_id: e(message, :id, nil),
            #     tab_id: "thread"
            #   )
          )
          # |> assign_new(:messages, fn -> LiveHandler.list_threads(current_user) |> e(:edges, []) end)
        }
      else
        _e ->
          {:error, l("Not found (or you don't have permission to view this message)")}
      end
    end
  end

  # show all my threads
  def handle_params(params, _url, socket) do
    current_user = current_user_required!(socket)

    # Determine filter tab based on params and user's DM privacy setting
    filter_tab = determine_filter_tab(params, current_user)

    # Always reload threads when tab changes
    threads = LiveHandler.list_threads(current_user, socket, tab: filter_tab)

    # |> debug("list_threads with tab: #{filter_tab}")

    {
      :noreply,
      socket
      |> assign(
        threads: threads,
        page_title: l("Direct Messages"),
        thread_active: false,
        filter_tab: filter_tab,
        composing_new: false,
        tab_id: nil
      )
    }
  end

  # Helper function to determine filter tab based on params and user settings
  defp determine_filter_tab(params, current_user) do
    case params["tab"] do
      nil ->
        # No explicit tab, use user's DM privacy setting to determine default
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

  def handle_event("send_message", params, socket) do
    participants_id = socket.assigns.participants |> Enum.map(fn user -> id(user) end)
    # debug(participants_id, "participants_id")

    new_params =
      params
      |> Map.put("to_circles", participants_id)

    # |> debug("params")

    Bonfire.Messages.LiveHandler.send_message(new_params, socket)
  end

  def handle_event("remove", %{data: %{"field" => field, "id" => id}}, socket) do
    {:noreply,
     socket
     |> update(maybe_to_atom(field), fn current_to_circles ->
       List.wrap(current_to_circles) -- [{id}]
       #  |> debug("v")
     end)}
  end

  # Add handler for PubSub messages
  def handle_info({:new_message, _}, socket) do
    current_user = current_user_required!(socket)

    # TODO: check if we're already viewing this thread?
    # current_thread_id = e(assigns(socket), :thread_id, nil)

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
