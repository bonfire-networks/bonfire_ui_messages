Code.eval_file("mess.exs", (if File.exists?("#{File.cwd!()}/../../lib/mix/mess.exs"), do: "#{File.cwd!()}/../../lib/mix/"))
defmodule Bonfire.UI.Messages.MixProject do

  use Mix.Project

  def project do
    if System.get_env("AS_UMBRELLA") == "1" do
      [
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock"
      ]
    else
      []
    end
    ++
    [
      app: :bonfire_ui_messages,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:surface],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: Mess.deps([
        {:phoenix_live_reload, "~> 1.2", only: :dev},
        {:floki, ">= 0.0.0", only: [:dev, :test]},
        {:bonfire_tag, git: "https://github.com/bonfire-networks/bonfire_tag",  optional: true, runtime: false},
        # {:phoenix_test, "~> 0.6", only: :test, runtime: false},
      ]),
      package: [
        licenses: ["AGPL v3"]
      ]
    ]
  end

  def application, do: [ extra_applications: [:logger, :runtime_tools] ]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]


  defp aliases do
    [
      "hex.setup": ["local.hex --force"],
      "rebar.setup": ["local.rebar --force"],
      "js.deps.get": ["cmd npm install --prefix assets"],
      "ecto.seeds": ["run priv/repo/seeds.exs"],

      setup: ["hex.setup", "rebar.setup", "deps.get", "ecto.setup", "js.deps.get"],
      updates: ["deps.get", "ecto.migrate", "js.deps.get"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "ecto.seeds"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

end
