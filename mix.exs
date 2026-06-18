defmodule Kathikon.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :kathikon,
      version: @version,
      elixir: "~> 1.18",
      name: "Kathikon",
      description: "BEAM-native durable job queue and task execution platform",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        sobelow: :dev
      ],
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
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "kathikon",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      maintainers: ["Thanos Vassilakis"],
      links: %{"GitHub" => "https://github.com/thanos/kathikon"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/thanos/kathikon/blob/main",
      extras: extras(),
      groups_for_modules: [
        API: ~r/^Kathikon$/,
        Core: ~r/^Kathikon\.(Job|Worker|Config|Storage|Telemetry)$/,
        Runtime: ~r/^Kathikon\.(Application|Queue|Dispatcher|Scheduler|Pruner)$/,
        Backend: ~r/^Kathikon\.Backend\./
      ],
      groups_for_extras: [
        Introduction: ~r/(^README|docs\/documentation)/i,
        Guides: ~r/docs\/guides\//,
        Reference: ~r/docs\/reference\//,
        Design: ~r/(docs\/phase-1-|plans\/)/,
        Livebook: ~r/livebooks\//
      ]
    ]
  end

  defp extras do
    [
      "docs/guides/quick-start.md",
      "docs/guides/workers.md",
      "docs/guides/queues-and-concurrency.md",
      "docs/guides/scheduling.md",
      "docs/guides/retries-and-errors.md",
      "docs/guides/cancellation.md",
      "docs/guides/telemetry-and-observability.md",
      "docs/guides/configuration.md",
      "docs/guides/storage-and-embedding.md",
      "docs/reference/modules.md",
      "README.md",
      "LICENSE": [title: "License"],
      "docs/documentation.md": [title: "Documentation"],
      "livebooks/kathikon_demo.livemd": [title: "Interactive demo"]
    ]
  end
end
