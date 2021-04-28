# Automerge

<!-- MDOC !-->

WARNING: This is currently not ready for production. This is based on the `performance` branch of the automerge javascript project which is currently an unreleased version. Additionally, this is far from optimized and there are likely to be breaking changes. Contributions welcomed.


```elixir
iex> doc = Automerge.from!(%{"cards" => Automerge.list()})
iex> {doc1, _patch} = Automerge.change!(doc, "Add Card", fn doc ->
...>  update_in(doc["cards"], &Automerge.List.append(&1, %{"title" => "Rewrite everything in Clojure", "done" => false}))
...> end)
iex> {_doc2, _patch} = Automerge.change!(doc1, "Add another card", fn doc ->
...> update_in(doc["cards"], &Automerge.List.append(&1, %{"title" => "Rewrite everything in Haskell", "done" => false}))
...> end)
```

## Installation

The package can be installed by adding `automerge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:automerge, "~> 0.1.0"}
  ]
end
```

<!-- MDOC !-->
