defmodule Bonfire.UI.Messages.MessageThreadsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Messages.LiveHandler

  prop threads, :any, default: nil
  prop thread_id, :string, default: nil
  prop tab_id, :string, default: nil
  prop context, :any, default: nil
  prop showing_within, :atom, default: nil
  prop thread_active, :boolean, default: false

  def permalink(thread, object) do
    thread_url =
      if thread do
        "/messages/#{uid(thread)}"
      end

    if thread_url && uid(thread) != uid(object) do
      "#{thread_url}#comment_#{uid(object)}"
    else
      "/messages/#{uid(object)}"
    end
  end
end
