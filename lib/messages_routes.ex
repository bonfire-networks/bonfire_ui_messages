defmodule Bonfire.UI.Messages.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/", Bonfire.UI.Messages do
        pipe_through(:browser)
      end

      # pages you need to view as a user
      scope "/", Bonfire.UI.Messages do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/message/:id", MessagesLive)

        live("/messages/:id", MessagesLive, as: Bonfire.Data.Social.Message)
        live("/messages/:id/reply/:reply_id", MessagesLive, as: Bonfire.Data.Social.Message)

        live("/messages/:id/reply/:level/:reply_id", MessagesLive,
          as: Bonfire.Data.Social.Message
        )

        live("/messages/@:username", MessagesLive, as: Bonfire.Data.Social.Message)
        live("/messages", MessagesLive, as: Bonfire.Data.Social.Message)
      end

      # pages you need an account to view
      scope "/", Bonfire.UI.Messages do
        pipe_through(:browser)
        pipe_through(:account_required)
      end
    end
  end
end
