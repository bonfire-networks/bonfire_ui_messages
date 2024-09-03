defmodule Bonfire.UI.Messages.SidebarMessagesMobileLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop threads, :any
  prop context, :any, default: nil
  prop thread_id, :string

  def permalink(thread, object) do
    thread_url =
      if thread do
        "/messages/#{uid(thread)}"
      end

    if thread_url && uid(thread) != uid(object) do
      "#{thread_url}##{uid(object)}"
    else
      "/messages/#{uid(object)}"
    end
  end
end
