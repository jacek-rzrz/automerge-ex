defmodule Automerge.AccessTest do
  use Automerge.HelperCase, async: true

  @root_id "_root"

  alias Automerge.Frontend
  alias Automerge.Backend.NIF, as: Backend

  describe "nested data structures" do
    @tag :wish_list
    test "Access.all/0" do
      assert_raise RuntimeError, ~r/Access.at\/1 expected a list/, fn ->
        doc =
          Automerge.from!(%{
            "name" => "john",
            "languages" =>
              Automerge.list([
                %{"name" => "elixir", "type" => "functional"},
                %{"name" => "c", "type" => "procedural"}
              ])
          })

        {doc, change} =
          Automerge.change!(doc, fn doc ->
            update_in(doc, ["languages", Access.all(), "name"], fn name ->
              {name, String.upcase(name)}
            end)
          end)

        assert Automerge.get_document(doc) == %{
                 "name" => "john",
                 "languages" => [
                   %{"name" => "ELIXIR", "type" => "functional"},
                   %{"name" => "C", "type" => "procedural"}
                 ]
               }
      end
    end

    @tag :wish_list
    test "Access.at/1" do
      assert_raise RuntimeError, ~r/Access.at\/1 expected a list/, fn ->
        doc = Automerge.from!([%{"name" => "john"}, %{"name" => "mary"}])

        {doc, change} =
          Automerge.change!(doc, fn doc ->
            update_in(doc, [Access.at(1), "name"], fn name ->
              String.capitalize(name)
            end)

            doc
          end)

        assert Automerge.get_document(doc) == [%{"name" => "john", "name" => "Mary"}]
      end
    end
  end
end
