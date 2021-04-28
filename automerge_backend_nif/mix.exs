defmodule Automerge.Backend.NIF.MixProject do
  use Mix.Project

  @version "0.1.0-alpha"

  def project do
    [
      app: :automerge_backend_nif,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:rustler] ++ Mix.compilers(),
      rustler_crates: [automerge_backend_nif: []]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.21.1"},
      {:elixir_uuid, "~> 1.6", hex: :uuid_utils, only: :test}
    ]
  end
end
