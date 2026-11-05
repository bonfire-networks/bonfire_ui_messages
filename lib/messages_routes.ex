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

        # a message is read in its discussion (`/discussion/:id`), and this page showed nothing for one; may come back as the conversation's own page
        # live("/message/:id", MessagesLive)

        # `as:` moved to the `/discussion/...` routes, so a message's path is its discussion
        # live("/messages/:id", MessagesLive, as: Bonfire.Data.Social.Message)
        # live("/messages/:id/reply/:reply_id", MessagesLive, as: Bonfire.Data.Social.Message)
        # live("/messages/:id/reply/:level/:reply_id", MessagesLive,
        #   as: Bonfire.Data.Social.Message
        # )

        # a message is read in its discussion, and these showed nothing for one; may come back as the conversation's own page
        # live("/messages/:id", MessagesLive)
        # live("/messages/:id/reply/:reply_id", MessagesLive)
        # live("/messages/:id/reply/:level/:reply_id", MessagesLive)

        # no `as:`: with one param like `/discussion/:id`, it could take over a message's path
        # live("/messages/@:username", MessagesLive, as: Bonfire.Data.Social.Message)
        live("/messages/@:username", MessagesLive)

        # a named helper instead: as a route with no params, it took `path(message)`, through the query-string clause the reverse router gives it, which has the same arity as `path(Message, id)`
        # live("/messages", MessagesLive, as: Bonfire.Data.Social.Message)
        live("/messages", MessagesLive, as: :messages)
      end

      # pages you need an account to view
      scope "/", Bonfire.UI.Messages do
        pipe_through(:browser)
        pipe_through(:account_required)
      end
    end
  end
end
