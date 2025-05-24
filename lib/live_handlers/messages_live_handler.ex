defmodule Bonfire.Messages.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  alias Bonfire.Messages

  def handle_params(%{"after" => cursor, "context" => context} = _attrs, _, socket) do
    live_more(context, [after: cursor], socket)
  end

  def handle_params(%{"before" => cursor, "context" => context} = _attrs, _, socket) do
    live_more(context, [before: cursor], socket)
  end

  def handle_event("load_more", attrs, socket) do
    current_user = current_user(socket)

    if is_nil(current_user) do
      {:noreply, assign_flash(socket, :error, l("User not found"))}
    else
      pagination = input_to_atoms(attrs)

      try do
        # Load just the next page of threads
        new_threads =
          Messages.list(current_user, nil, [latest_in_threads: true] ++ [pagination: pagination])

        # Get current threads from socket assigns
        current_threads = e(assigns(socket), :threads, %{edges: [], page_info: %{}})

        # Append new threads to existing ones
        updated_threads = %{
          edges: e(current_threads, :edges, []) ++ e(new_threads, :edges, []),
          page_info: e(new_threads, :page_info, %{})
        }

        {:noreply,
         socket
         |> assign(
           threads: updated_threads,
           loading: false
         )}
      rescue
        error ->
          error(error, "Failed to load more messages")
          {:noreply, assign_flash(socket, :error, l("Could not load more messages"))}
      end
    end
  end

  def handle_event("preload_more", attrs, socket) do
    # Same as load_more but for infinite scroll preloading
    handle_event("load_more", attrs, socket)
  end

  def handle_event("send", params, socket) do
    send_message(params, socket)
  end

  def handle_event("select_recipient", %{"id" => id, "action" => "deselect"}, socket) do
    debug(id, "remove from circles")
    # debug(e(assigns(socket), :to_circles, []))
    to_circles =
      Enum.reject(e(assigns(socket), :to_circles, []), fn {_name, cid} -> cid == id end)
      |> debug()

    {:noreply, assign(socket, to_circles: to_circles)}
  end

  def handle_event("select_recipient", %{"id" => id, "name" => name}, socket) do
    debug(id, "add to circles")
    # debug(e(assigns(socket), :to_circles, []))
    to_circles =
      [{name, id} | e(assigns(socket), :to_circles, [])]
      |> Enum.uniq()

    # |> debug()
    {:noreply, assign(socket, to_circles: to_circles)}
  end

  def live_more(context, opts, socket) do
    debug(opts, "paginate threads")
    current_user = current_user(assigns(socket))

    if is_nil(current_user) do
      {:noreply, assign_flash(socket, :error, l("User not found"))}
    else
      try do
        # Load just the next page of threads
        new_threads =
          Messages.list(current_user, context, [latest_in_threads: true] ++ List.wrap(opts))

        # Get current threads from widget or socket assigns
        current_threads = e(assigns(socket), :threads, %{edges: [], page_info: %{}})

        # Append new threads to existing ones
        updated_threads = %{
          edges: e(current_threads, :edges, []) ++ e(new_threads, :edges, []),
          page_info: e(new_threads, :page_info, %{})
        }

        {:noreply,
         socket
         |> assign(
           threads: updated_threads,
           sidebar_widgets:
             threads_widget(
               current_user,
               context,
               [
                 tab_id: nil,
                 thread_id: e(assigns(socket), :thread_id, nil),
                 threads: updated_threads
               ] ++ List.wrap(opts)
             ),
           loading: false
         )}
      rescue
        error ->
          error(error, "Failed to load more threads")
          {:noreply, assign_flash(socket, :error, l("Could not load more threads"))}
      end
    end
  end

  def threads_widget(current_user, user \\ nil, opts \\ []) do
    # Use passed threads or load them fresh
    threads = opts[:threads] || list_threads(current_user, user, opts)

    [
      users: [
        main: [
          {Bonfire.UI.Messages.MessageThreadsLive,
           [
             context: uid(user),
             showing_within: :messages,
             threads: threads,
             thread_id: opts[:thread_id]
           ] ++ List.wrap(opts)}
        ]
        # secondary: [
        #   {Bonfire.Tag.Web.WidgetTagsLive, []}
        # ]
      ]
    ]
  end

  def list_threads(current_user, user \\ nil, opts \\ []) do
    # Use config pagination limit unless overridden
    default_limit = Bonfire.Common.Config.get(:default_pagination_limit, 8)

    if current_user,
      do:
        Messages.list(
          current_user,
          user,
          [latest_in_threads: true, limit: default_limit] ++ List.wrap(opts)
        )
        # |> debug()
        |> repo().maybe_preload(activity: [replied: [thread: :named]])
  end

  def thread_participants(thread_id, activity, object, opts) do
    current_user = current_user(opts)

    if(not is_nil(object), do: Map.put(activity, :object, object), else: activity)
    |> Bonfire.Social.Threads.list_participants(
      thread_id,
      current_user: current_user,
      skip_boundary_check: true
    )
  end

  def thread_meta(key, thread_id, activity, object, opts) do
    thread_meta(thread_id, activity, object, opts)
    |> Map.get(key)
  end

  def thread_meta(thread_id, activity, object, opts) do
    participants =
      thread_participants(thread_id, activity, object, opts)
      |> debug(thread_id)

    # to_circles =
    #   if is_list(participants) and participants !=[],
    #     do:
    #       participants
    #       |> Enum.reject(&(&1.id == current_user.id))
    #       |> Enum.map(&{e(&1, :character, :username, l("someone")), e(&1, :id, nil)})

    names =
      if is_list(participants) and participants != [],
        do:
          participants
          |> Enum.reject(&(&1.id == current_user_id(opts)))
          |> Enum.map_join(
            " & ",
            &e(&1, :profile, :name, e(&1, :character, :username, l("someone else")))
          )

    # mentions = if length(participants)>0, do: Enum.map_join(participants, " ", & "@"<>e(&1, :character, :username, ""))<>" "

    #  if mentions, do: "for %{people}", people: mentions), else: l "Note to self..."
    # prompt = l("Compose a thoughtful response")

    # l("Conversation between %{people}", people: names)
    title = if names && names != "", do: names, else: l("Note to self")

    %{
      participants: participants,
      names: names,
      title: title
    }
    |> debug(thread_id)
  end

  def send_message(params, socket) do
    attrs =
      params
      |> debug("attrs")
      |> input_to_atoms()
      # workaround for input_to_atoms discarding non-atom circle ids
      |> Map.put(:to_circles, params["to_circles"])

    with {:ok, sent} <-
           Messages.send([context: assigns(socket)[:__context__] || current_user(socket)], attrs) do
      # debug(sent, "sent!")
      message_sent(sent, attrs, socket)
      # else e ->
      #   debug(message_error: e)
      #   {:noreply,
      #     socket
      #     |> assign_flash(:error, "Could not send...")
      #   }
    end
  end

  defp message_sent(_sent, %{reply_to: %{thread_id: thread_id}} = _attrs, socket)
       when is_binary(thread_id) and thread_id != "" do
    # FIXME: assign or pubsub the new message and patch instead
    {:noreply,
     socket
     |> push_event("smart_input:reset", %{})
     |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()}
    |> assign_flash(:info, l("Sent!"))

    #  |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()}
  end

  defp message_sent(_sent, _attrs, socket) do
    {
      :noreply,
      socket
      |> push_event("smart_input:reset", %{})
      |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
      |> assign_flash(:info, l("Sent!"))
      #  |> redirect_to("/messages/#{e(sent, :replied, :thread_id, nil) || uid(sent)}##{uid(sent)}")
    }
  end
end
