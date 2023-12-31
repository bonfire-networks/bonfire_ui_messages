defmodule Bonfire.UI.Messages.Repo.Migrations.ImportMe  do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Messages.Migration
  # accounts & users

  def change, do: migrate_social

end
