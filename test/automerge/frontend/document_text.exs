defmodule Automerge.Frontend.DocumentTest do
  use ExUnit.Case, async: true

  describe "get_in" do
  end

  describe "put_in" do
    test "creates new objects" do
      document = Automerge.init()

      {document1, changes} = Automerge.change!(document, &put_in(&1, ["test"], ["a"]))
      {document2, changes} = Automerge.change!(document1, &put_in(&1, ["test"], ["b"]))
      {document2, changes} = Automerge.change!(document1, &put_in(&1, ["test"], ["c"]))
    end

    test "can perform multiple operations in change!" do
      actor_id = UUID.uuid4()

      {_document, req} =
        Automerge.init(actor_id: actor_id)
        |> Automerge.change!(fn doc ->
          doc
          |> put_in(["magpies"], 2)
          |> put_in(["sparrows"], 15)
        end)

      assert req == %{
               "actor" => actor_id,
               "deps" => %{},
               "ops" => [
                 %{
                   "action" => "set",
                   "key" => "magpies",
                   "obj" => "00000000-0000-0000-0000-000000000000",
                   "value" => 2
                 },
                 %{
                   "action" => "set",
                   "key" => "sparrows",
                   "obj" => "00000000-0000-0000-0000-000000000000",
                   "value" => 15
                 }
               ],
               "request_type" => "change",
               "seq" => 1
             }
    end
  end

  describe "get_in_and_update" do
    test "can put a simple value" do
      document = Automerge.init()

      {document1, changes} =
        Automerge.change!(document, fn doc -> put_in(doc, ["test"], Automerge.list(["a"])) end)

      {document2, changes} =
        Automerge.change!(document1, fn doc ->
          {_value, doc} = get_and_update_in(doc, ["test"], &{&1, ["b"]})

          doc
        end)

      {document2, changes} =
        Automerge.change!(document1, fn doc ->
          {_value, doc} = get_and_update_in(doc, ["test"], &{&1, ["c"]})

          doc
        end)
    end

    test "pop list" do
    end

    test "pop map" do
    end
  end

  describe "update_in" do
    test "add a list item to an empty list" do
      {doc, _changes} =
        %{"cards" => Automerge.list()}
        |> Automerge.from!()
        |> Automerge.change!("Add card", fn doc ->
          update_in(
            doc,
            ["cards"],
            &(&1 ++ [%{"title" => "Rewrite everything in Clojure", "done" => false}])
          )
        end)

      assert Automerge.get_document(doc) == %{
               "cards" => [%{"title" => "Rewrite everything in Clojure", "done" => false}]
             }
    end

    test "update a list item" do
      {doc, _changes} =
        %{"cards" => Automerge.list()}
        |> Automerge.from!()
        |> Automerge.change!("Add card", fn doc ->
          update_in(
            doc,
            ["cards"],
            &(&1 ++ [%{"title" => "Rewrite everything in Elixir", "done" => false}])
          )
        end)

      {doc, _changes} =
        Automerge.change!(doc, "Update card", fn doc ->
          update_in(doc, ["cards", Access.at(0)], &Map.put(&1, "done", true))
        end)

      assert Automerge.get_document(doc) == %{
               "cards" => [%{"title" => "Rewrite everything in Elixir", "done" => true}]
             }
    end
  end

  describe "pop_in" do
  end

  describe "Map" do
  end

  describe "List" do
    test "insert_at" do
      document = Automerge.init()

      {document1, changes} = Automerge.change!(document, &put_in(&1["list"], Automerge.list()))

      {document2, changes} =
        Automerge.change!(
          document1,
          &update_in(&1, ["list", Access.at(0)], fn list -> list ++ [2, 3] end)
        )
    end
  end

  describe "Text" do
  end
end
