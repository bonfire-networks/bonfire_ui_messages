defmodule Bonfire.UI.Messages.ContactPickerSearchTest do
  @moduledoc """
  The contact picker is how DM recipients are searched (it replaced the
  live_select-based `SelectRecipientsLive`). Its `search_contacts` event calls
  `Bonfire.Me.Users.search/2`, the same root as every live_select user search.
  """
  use Bonfire.UI.Messages.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  setup do
    account = fake_account!()
    me = fake_user!(account)
    findable = fake_user!(account, %{name: "Findable Contact"})

    {:ok, account: account, me: me, findable: findable}
  end

  test "searching contacts returns matching users", %{me: me, findable: findable} do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:__context__, %{current_user: me})

    assert {:noreply, socket} =
             Bonfire.UI.Messages.ContactPickerLive.handle_event(
               "search_contacts",
               %{"search" => "findable"},
               socket
             )

    assert Enum.any?(socket.assigns.search_results, &(Enums.id(&1) == findable.id))

    for user <- socket.assigns.search_results do
      assert e(user, :profile, :name, nil) || e(user, :character, :username, nil),
             "results need profile/character loaded to be displayed"
    end
  end

  test "short search terms return no results instead of erroring", %{me: me} do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:__context__, %{current_user: me})

    assert {:noreply, socket} =
             Bonfire.UI.Messages.ContactPickerLive.handle_event(
               "search_contacts",
               %{"search" => "f"},
               socket
             )

    assert socket.assigns.search_results == []
  end
end
