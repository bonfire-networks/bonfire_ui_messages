defmodule Bonfire.UI.Messages.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    # Messages: optional title/subject (toggle) and content-warning siren.
    config :bonfire_ui_common, Bonfire.UI.Common.InputControlsLive,
      enable_fields: [
        title: [message: [enable_toggle: true]],
        sensitive: [message: [enable_toggle: true]]
      ]
  end
end
