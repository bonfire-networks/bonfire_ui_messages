defmodule Bonfire.UI.Messages.NewConversationLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop recipients, :list, default: []
  prop compose_user, :any, default: nil
  prop filter_tab, :string, default: "all"

  def recipient_names(recipients, compose_user) do
    case recipients do
      [_ | _] ->
        Enum.map_join(recipients, " & ", fn {_id, name} -> name end)

      _ when not is_nil(compose_user) ->
        e(compose_user, :profile, :name, nil) ||
          e(compose_user, :character, :username, l("someone"))

      _ ->
        nil
    end
  end
end
