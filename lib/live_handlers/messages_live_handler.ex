defmodule Bonfire.Messages.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  alias Bonfire.Messages

  def handle_params(%{"after" => cursor} = attrs, _, socket) do
    live_more(attrs["context"], [after: cursor], socket)
  end

  def handle_params(%{"before" => cursor} = attrs, _, socket) do
    live_more(attrs["context"], [before: cursor], socket)
  end

  def handle_event("load_more", %{"context" => "contacts"} = attrs, socket) do
    load_more_contacts(attrs, socket)
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
          |> enrich_threads_with_participants(current_user)

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

  def handle_event("preload_more", %{"context" => "contacts"} = attrs, socket) do
    load_more_contacts(attrs, socket)
  end

  def handle_event("preload_more", attrs, socket) do
    # Same as load_more but for infinite scroll preloading
    handle_event("load_more", attrs, socket)
  end

  defp load_more_contacts(attrs, socket) do
    # NOTE: When called via LiveHandler dispatch with target={@myself} on the ContactPickerLive
    # component, the socket here IS the component's socket (has suggested_users assign)
    current_user = current_user(socket)

    if is_nil(current_user) do
      {:noreply, socket}
    else
      pagination = input_to_atoms(attrs)

      result =
        Bonfire.Social.Graph.Follows.list_my_followed(current_user,
          type: Bonfire.Data.Identity.User,
          limit: 20,
          pagination: pagination
        )

      new_edges =
        result
        |> e(:edges, result)
        |> Enum.map(&e(&1, :edge, :object, nil))
        |> Enum.reject(&is_nil/1)

      current = e(assigns(socket), :suggested_users, %{edges: [], page_info: nil})

      updated = %{
        edges: e(current, :edges, []) ++ new_edges,
        page_info: e(result, :page_info, nil)
      }

      {:noreply, assign(socket, suggested_users: updated)}
    end
  end

  def handle_event("search_threads", %{"search" => search_term}, socket) do
    search_term = String.trim(search_term)
    search_term = if search_term == "", do: nil, else: search_term
    {:noreply, assign(socket, search_term: search_term)}
  end

  def handle_event("toggle_contact_picker", _params, socket) do
    composing_new = !e(assigns(socket), :composing_new, false)

    {:noreply,
     assign(socket,
       composing_new: composing_new,
       selected_recipients: []
     )}
  end

  def handle_event("toggle_recipient", %{"id" => id, "name" => name}, socket) do
    selected = e(assigns(socket), :selected_recipients, [])

    updated =
      if Enum.any?(selected, fn {rid, _} -> rid == id end) do
        Enum.reject(selected, fn {rid, _} -> rid == id end)
      else
        [{id, name} | selected]
      end

    {:noreply, assign(socket, selected_recipients: updated)}
  end

  def handle_event("start_direct_message", _params, socket) do
    selected = e(assigns(socket), :selected_recipients, [])

    open_dm_composer(selected, socket)

    {:noreply,
     socket
     |> assign(composing_new: false)}
  end

  def handle_event("send_new_conversation", params, socket) do
    send_message(params, socket)
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

    {:noreply, assign(socket, to_circles: to_circles)}
  end

  @doc "Opens the portal SmartInput configured for DM composition with the given recipients."
  def open_dm_composer(to_circles, socket) do
    Bonfire.UI.Common.SmartInput.LiveHandler.open_with_text_suggestion(
      "",
      [
        to_boundaries: [{"message", l("Message")}],
        smart_input_opts: %{
          create_object_type: :message,
          recipients_editable: false,
          to_circles: to_circles
        }
      ],
      socket
    )

    # Also update PersistentLive's socket so @to_circles flows through the template
    persistent_pid = e(assigns(socket), :__context__, :child_pid, nil)

    if persistent_pid do
      send(
        persistent_pid,
        {:assign_persistent_self,
         %{to_circles: to_circles, to_boundaries: [{"message", l("Message")}]}}
      )
    end
  end

  def live_more(context, opts, socket) do
    debug(opts, "paginate threads")
    current_user = current_user(socket)

    if is_nil(current_user) do
      {:noreply, assign_flash(socket, :error, l("User not found"))}
    else
      try do
        # Load just the next page of threads
        new_threads =
          Messages.list(current_user, context, [latest_in_threads: true] ++ List.wrap(opts))
          |> enrich_threads_with_participants(current_user)

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
           #  sidebar_widgets:
           #    threads_widget(
           #      current_user,
           #      context,
           #      [
           #        tab_id: nil,
           #        thread_id: e(assigns(socket), :thread_id, nil),
           #        threads: updated_threads
           #      ] ++ List.wrap(opts)
           #    ),
           loading: false
         )}
      rescue
        error ->
          error(error, "Failed to load more threads")
          {:noreply, assign_flash(socket, :error, l("Could not load more threads"))}
      end
    end
  end

  # def threads_widget(current_user, user \\ nil, opts \\ []) do
  #   # Use passed threads or load them fresh
  #   threads = opts[:threads] || list_threads(current_user, user, opts)

  #   [
  #     users: [
  #       main: [
  #         {Bonfire.UI.Messages.MessageThreadsLive,
  #          [
  #            context: uid(user),
  #            showing_within: :messages,
  #            threads: threads,
  #            thread_id: opts[:thread_id]
  #          ] ++ List.wrap(opts)}
  #       ]
  #       # secondary: [
  #       #   {Bonfire.Tag.Web.WidgetTagsLive, []}
  #       # ]
  #     ]
  #   ]
  # end

  def list_threads(current_user, user \\ nil, opts \\ []) do
    # Use config pagination limit unless overridden
    default_limit = Bonfire.Common.Config.get(:default_pagination_limit, 8)

    # Handle tab-based filtering 
    tab = opts[:tab] || "all"

    relationship_filter =
      case tab do
        # Show only messages from followed users
        "followed_only" -> :followed_only
        # Show messages from users not followed
        "not_followed" -> :not_followed
        # Show all messages
        _ -> :all
      end

    opts =
      opts
      |> Keyword.put(:relationship_filter, relationship_filter)
      # We're not using show_filtered anymore
      |> Keyword.put(:show_filtered, false)

    # IO.inspect({:tab, tab, :filter, relationship_filter}, label: "TAB_AND_FILTER")

    if current_user do
      Messages.list(
        current_user,
        user,
        [latest_in_threads: true, limit: default_limit] ++ List.wrap(opts)
      )
      |> repo().maybe_preload(activity: [replied: [thread: :named]])
      |> enrich_threads_with_participants(current_user)
    end
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

    current_user_id = current_user_id(opts)

    names =
      if is_list(participants) and participants != [],
        do:
          participants
          |> Enum.reject(&(&1.id == current_user_id))
          |> Enum.map_join(
            " & ",
            &(e(&1, :profile, :name, nil) || e(&1, :character, :username, l("someone else")))
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

    # |> debug(thread_id)
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
      message_sent(sent, attrs, socket)
    else
      e ->
        debug(message_error: e)

        {:noreply,
         socket
         |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
         |> assign_flash(:error, l("Could not send the message"))}
    end
  end

  defp message_sent(_sent, %{reply_to: %{thread_id: thread_id}} = _attrs, socket)
       when is_binary(thread_id) and thread_id != "" do
    # FIXME: assign or pubsub the new message and patch instead
    {:noreply,
     socket
     |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
     |> assign_flash(:info, l("Sent!"))}
  end

  defp message_sent(sent, _attrs, socket) do
    thread_id = e(sent, :replied, :thread_id, nil) || uid(sent)

    {:noreply,
     socket
     |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
     |> assign_flash(
       :info,
       "<a href='/discussion/#{thread_id}' class='link link-hover font-semibold'>#{l("Sent!")} →</a>"
     )}
  end

  defp enrich_threads_with_participants(threads, current_user) do
    # NOTE: maybe instead of loading/computing the list of thread participants & names we should compute that once and set the names in thread name/title

    current_user_id = id(current_user)

    # Preload tags (DM recipients) on thread edges so list_participants_for_threads can extract them
    thread_edges =
      e(threads, :edges, [])
      |> repo().maybe_preload(activity: [object: [tags: [:character, profile: :icon]]])

    # Single batch query for all threads' participants (eliminates N+1)
    # current_user excluded at DB level; known tag recipients excluded inside list_participants_for_threads
    participants_by_thread =
      Bonfire.Social.Threads.list_participants_for_threads(
        thread_edges,
        current_user: current_user,
        skip_boundary_check: true,
        limit: 5,
        exclude_subject_ids: [current_user_id]
      )

    # |> debug("participants_by_thread")

    thread_edges =
      Enum.map(thread_edges, fn
        %{activity: %{replied: %{thread_id: thread_id}} = activity} = edge
        when is_binary(thread_id) ->
          other_participants = Map.get(participants_by_thread, thread_id, [])

          count = length(other_participants)

          names =
            case other_participants do
              [] ->
                nil

              others ->
                Enum.map_join(others, " & ", fn p ->
                  e(p, :profile, :name, nil) ||
                    e(p, :character, :username, nil) ||
                    l("someone")
                end)
            end

          %{
            edge
            | activity:
                activity
                # |> Map.put(:thread_participants, other_participants) # not used in component right now
                |> Map.put(:thread_other_participant, if(count == 1, do: hd(other_participants)))
                |> Map.put(:thread_participant_count, count)
                |> Map.put(:thread_participants_names, names)
          }

        edge ->
          edge
      end)

    Map.put(threads, :edges, thread_edges)
  end
end
