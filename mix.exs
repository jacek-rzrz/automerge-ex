defmodule Automerge.MixProject do
  use Mix.Project

  @version "0.1.0-alpha"

  def project do
    [
      app: :automerge,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Automerge",
      description: description(),
      source_url: "https://github.com/tylersamples/automerge-ex",
      docs: docs(),
      package: package(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_uuid, "~> 1.6", hex: :uuid_utils},
      {:automerge_backend_nif, path: "./automerge_backend_nif"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  def description do
    """

    """
  end

  def package do
    [
      name: "automerge",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tylersamples/automerge-ex"}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      source_url: "https://github.com/tylersamples/automerge",
      main: "Automerge"
    ]
  end

  defp aliases do
    [
      # run `mix setup` in all child apps
      ci: [
        "cmd mix credo --strict",
        "cmd mix format --check-formatted",
        "cmd mix deps.unlock --check-unused",
        "cmd MIX_ENV=test mix do compile --warnings-as-errors",
        "cmd mix test"
      ]
    ]
  end
end
