defmodule Bonfire.UI.Messages.MessageThreadsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Messages.LiveHandler

  prop threads, :any, default: nil
  prop thread_id, :string, default: nil
  prop tab_id, :string, default: nil
  prop context, :any, default: nil
  prop showing_within, :atom, default: nil
  prop thread_active, :boolean, default: false
  prop filter_tab, :string, default: "all"
  prop search_term, :string, default: nil
  prop composing_new, :boolean, default: false
  prop selected_recipients, :list, default: []

  def filter_threads(edges, nil), do: edges
  def filter_threads(edges, ""), do: edges

  def filter_threads(edges, search_term) do
    term = String.downcase(search_term)

    Enum.filter(edges, fn %{activity: activity} ->
      names = e(activity, :thread_participants_names, "") || ""
      thread_name = e(activity, :replied, :thread, :named, :name, "") || ""
      subject_name = e(activity, :subject, :profile, :name, "") || ""

      preview =
        e(activity, :object, :post_content, :name, "") ||
          e(activity, :object, :post_content, :summary, "") ||
          e(activity, :object, :post_content, :html_body, "") || ""

      String.contains?(String.downcase(names), term) ||
        String.contains?(String.downcase(thread_name), term) ||
        String.contains?(String.downcase(subject_name), term) ||
        String.contains?(String.downcase(preview), term)
    end)
  end

  @group_colors ~w(
    bg-red-400 bg-orange-400 bg-amber-400 bg-yellow-400
    bg-lime-400 bg-green-400 bg-emerald-400 bg-teal-400
    bg-cyan-400 bg-sky-400 bg-blue-400 bg-indigo-400
    bg-violet-400 bg-purple-400 bg-fuchsia-400 bg-pink-400
  )

  def messages_back_url(filter_tab) do
    case filter_tab do
      "followed_only" -> "/messages?tab=followed_only"
      "not_followed" -> "/messages?tab=not_followed"
      _ -> "/messages?tab=all"
    end
  end

  def group_avatar_color(thread_id) when is_binary(thread_id) do
    index = :erlang.phash2(thread_id, length(@group_colors))
    Enum.at(@group_colors, index)
  end

  def group_avatar_color(_), do: "bg-base-300"

  def permalink(replied, object) do
    permalink(replied, object, nil)
  end

  def permalink(replied, object, tab) do
    if mls_encrypted?(e(object, :post_content, :html_body, nil)) do
      # Encrypted MLS message — link to ap-mls:// deep link using the message's canonical URL
      case canonical_url(object) do
        "http" <> _ = url -> String.replace(url, ~r/^https?:\/\//, "ap-mls://")
        _ -> default_permalink(replied, object, tab)
      end
    else
      default_permalink(replied, object, tab)
    end
  end

  defp mls_encrypted?(body) when is_binary(body) do
    # TODO: actually store an indicator of MLS encryption in the message DB instead of relying on this heuristic
    clean = String.trim(body)
    byte_size(clean) > 64 and Regex.match?(~r/\A[A-Za-z0-9+\/=]+\z/, clean)
  end

  defp mls_encrypted?(_), do: false

  defp default_permalink(replied, object, tab) do
    thread_id = e(replied, :thread_id, nil)
    object_id = id(object)

    thread_url =
      if thread_id do
        "/messages/#{thread_id}"
      end

    base_url =
      if thread_url && thread_id != object_id do
        # e(assigns, :thread_level, nil) ||
        thread_level =
          length(e(replied, :path, []))

        if thread_level > 0 do
          "#{thread_url}/reply/#{thread_level}/#{object_id}"
        else
          "#{thread_url}/reply/#{object_id}"
        end
      else
        "/messages/#{object_id}"
      end

    # Add tab parameter if provided and valid
    case tab do
      tab when tab in ["all", "followed_only", "not_followed"] -> "#{base_url}?tab=#{tab}"
      _ -> base_url
    end
  end
end
