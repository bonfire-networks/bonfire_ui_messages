defmodule Bonfire.UI.Messages.MessagesLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  # alias Bonfire.Social
  alias Bonfire.Messages.LiveHandler
  import Untangle

  declare_extension("UI for messages",
    icon: "carbon:email",
    emoji: "✉️",
    description: l("User interface for writing and reading private messages.")
  )

  declare_nav_link(l("Direct Messages"),
    icon: "carbon:email",
    icon_active: "carbon:email",
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

    threads =
      (ed(assigns(socket), :threads, nil) || LiveHandler.list_threads(current_user, socket))
      |> debug("list_threads")

    {
      :ok,
      socket
      |> assign(
        nav_items: Bonfire.Common.ExtensionModule.default_nav(),
        showing_within: :messages,
        back: true,
        threads: threads,
        #  smart_input_opts: %{prompt: l("Message"), icon: "mdi:inbox"},
        #  smart_input_opts: [inline_only: true],
        # to_boundaries: [{"message", "Message"}],
        without_secondary_widgets: true,
        page_title: l("Messages"),
        page: "messages",
        page_header_icon: "carbon:email",
        no_index: true,
        feed_id: feed_id,
        activity: nil,
        object: nil,
        tab_id: nil,
        #  reply_to_id: nil,
        thread_id: nil,
        no_header: true,
        thread_mode: maybe_to_atom(e(params, "mode", nil)),
        feedback_title: l("No messages"),
        feedback_message: l("Select a thread or start a new one..."),
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

  def handle_params(%{"username" => username} = _params, _url, socket) do
    # view messages excanged with a particular user

    current_user = current_user_required!(socket)
    current_username = e(current_user, :character, :username, nil)

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
      # smart_input_text =
      #   if e(current_user, :character, :username, "") == e(user, :character, :username, ""),
      #     do: "",
      #     else: "@" <> e(user, :character, :username, "") <> " "

      # to_circles = [
      #   {e(user, :profile, :name, nil) || e(user, :character, :username, l("someone")), id(user)}
      # ]

      {:noreply,
       socket
       |> assign(
         page: "messages",
         # feed: e(feed, :edges, []),
         #  smart_input: true,
         tab_id: "compose",
         feed_title: l("Messages"),
         # the user to display
         user: user
         #  reply_to_id: nil,
         #  thread_id: nil,
         #  smart_input_opts: [prompt: l("Compose a thoughtful message...")],
         #  to_circles: to_circles || []
         #  sidebar_widgets:
         #    LiveHandler.threads_widget(current_user, uid(e(assigns(socket), :user, nil)),
         #      thread_id: nil,
         #      tab_id: "compose"
         #    )
       )}
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

  def handle_params(%{"id" => id} = _params, url, socket) do
    if not is_uid?(id) do
      handle_params(%{"username" => id}, url, socket)
    else
      # show a message thread

      current_user = current_user_required!(socket)

      with {:ok, message} <- Bonfire.Messages.read(id, current_user: current_user) do
        # debug(message, "the first message in thread")

        # TODO: clean up the following
        {activity, message} = Map.pop(message, :activity)
        {preloaded_object, activity} = Map.pop(activity, :object)
        message = Map.merge(message, preloaded_object)

        activity =
          Bonfire.Social.Activities.activity_preloads(activity, :all, current_user: current_user)
          |> debug("preloaded")

        # reply_to_id = e(params, "reply_to_id", nil)
        thread_id = e(activity, :replied, :thread_id, id)

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
        #           e(message, :post_content, :html_body, reply_to_id)
        #         )
        #       )
        #     )

        %{
          participants: participants,
          title: title
        } = LiveHandler.thread_meta(thread_id, activity, message, current_user: current_user)

        {
          :noreply,
          socket
          |> assign(
            page_title: e(activity, :replied, :thread, :named, :name, nil) || title,
            page: "messages",
            tab_id: "thread",
            # reply_to_id: reply_to_id,
            url: url,
            back: true,
            activity: activity,
            object: message,
            context_id: thread_id,
            thread_id: thread_id,
            # reply_to_id: thread_id,
            participants: participants,
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
  def handle_params(_params, _url, socket) do
    current_user = current_user_required!(socket)

    threads =
      (ed(assigns(socket), :threads, nil) || LiveHandler.list_threads(current_user, socket))
      |> debug("list_threads")

    {
      :noreply,
      socket
      |> assign(
        threads: threads,
        page_title: l("Direct Messages"),

        # to_boundaries: [{"message", "Message"}],
        tab_id: nil
      )
    }
  end

  def handle_event("send_message", params, socket) do
    IO.inspect(params, label: "cazz")
    participants_id = socket.assigns.participants |> Enum.map(fn user -> id(user) end)
    debug(participants_id, "participants_id")

    new_params =
      params
      |> Map.put("to_circles", participants_id)
      |> debug("params")

    Bonfire.Messages.LiveHandler.send_message(new_params, socket)
  end

  def handle_event("remove", %{data: %{"field" => field, "id" => id}}, socket) do
    {:noreply,
     socket
     |> update(maybe_to_atom(field) |> debug("f"), fn current_to_circles ->
       (List.wrap(current_to_circles) -- [{id}])
       |> debug("v")
     end)}
  end
end
