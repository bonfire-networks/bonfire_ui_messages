defmodule Bonfire.UI.Messages.MessageThreadsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Messages.LiveHandler

  prop threads, :any, default: nil
  prop thread_id, :string, default: nil
  prop tab_id, :string, default: nil
  prop context, :any, default: nil
  prop showing_within, :atom, default: nil
  prop thread_active, :boolean, default: false

  def permalink(replied, object) do
    thread_id = e(replied, :thread_id, nil)
    object_id = id(object)

    thread_url =
      if thread_id do
        "/messages/#{thread_id}"
      end

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
  end
end
