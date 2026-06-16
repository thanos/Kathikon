defmodule Kathikon.MixProject do
  use Mix.Project

  def project do
    [
      app: :kathikon,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Kathikon.Application, []},
      extra_applications: [:logger, :mnesia, :telemetry]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4", only: [:dev, :test]}
    ]
  end
end
