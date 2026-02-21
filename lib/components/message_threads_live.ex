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
