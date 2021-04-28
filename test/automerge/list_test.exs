defmodule Automerge.ListTest do
  use Automerge.HelperCase, async: true

  ## Elixir's List effects on the data structure

  describe "Elixir.List" do
    test "Receives an error when attempting to use the Elixir.List module" do
      doc = Automerge.from!(%{"list" => Automerge.list()})

      # Sadly can't use the Elixir.List module functions and instead have to use the Automerge.List functions instead.
      # Annoyingly confusing error :/ sry
      assert_raise FunctionClauseError, "no function clause matching in List.insert_at/3", fn ->
        Automerge.change!(doc, fn doc ->
          List.insert_at(doc["list"], 0, "foo")
        end)
      end
    end
  end

  ## Elixir's list related kernel functions

  describe "Elixir.Kernel" do
    test "++" do
      doc = Automerge.from!(%{"list" => Automerge.list()})

      # Sadly can't support ++. The value provided in the callback, list below, is a struct and not an Elixir list. Can't change this :/ nor the terribly confusing error.
      assert_raise ArgumentError, "argument error", fn ->
        Automerge.change!(doc, &update_in(&1["list"], fn list -> list ++ ["element"] end))
      end
    end

    test "--" do
      doc = Automerge.from!(%{"list" => Automerge.list([1, 2, 3])})

      # Sadly can't support --. See ++'s comment.
      assert_raise ArgumentError, "argument error", fn ->
        Automerge.change!(doc, &update_in(&1["list"], fn list -> list -- [1, 2] end))
      end
    end

    test "sigil_w" do
      doc = Automerge.from!(%{"list" => Automerge.list(~w(a b c))})

      assert Automerge.get_document(doc) == %{"list" => ["a", "b", "c"]}

    end
  end

  ## Automerge.List's Enumerable protocol

  describe "enumerable count" do
    test "empty list count" do
      doc = Automerge.from!(%{"list" => Automerge.list()})

      assert Enum.count(doc["list"]) === 0
    end

    test "list with lots of items" do
      doc = Automerge.from!(%{"list" => 0..999 |> Enum.to_list() |> Automerge.list()})

      assert Enum.count(doc["list"]) === 1000
    end
  end

  describe "enumerable slice" do
    test "at/2" do
      doc = Automerge.from!(%{"list" => 0..999 |> Enum.to_list() |> Automerge.list()})

      # 30 is Wololo in Age of Empires II.
      assert Enum.at(doc["list"], 30) === 30
    end
  end

  ## Automerge.Map's Access Behaviour

  describe "get_in" do
    setup do
      s1 = Automerge.from!(%{"list" => Automerge.list([1, 2, %{"subobject" => "value"}])})

      [s1: s1]
    end

    test "opaque from the outside", %{s1: s1} do
      person1 = s1["person1"]

      # Despite us attempting to go into the object it should return the parent. This behaviour is
      # so Automerge.get_object_id/1 works as expected.
      assert person1 == get_in(person1, [1])
    end
  end

  describe "get_and_update" do
    setup do
      s1 = Automerge.from!(%{"list" => Automerge.list([1, 2, %{"subobject" => "value"}])})

      [s1: s1]
    end

    test "blows up when outside a change fn", %{s1: s1} do
      assert_raise RuntimeError,
                   "Can only modify the document inside of change!/2 or change!/3 callback",
                   fn ->
                     get_and_update_in(s1["list"], fn person1 ->
                       put_in(person1[2], 5)
                     end)
                   end
    end

    test "allow for updating when it's invoked inside a change fn", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["list"], fn person1 ->
            put_in(person1[0], "zero")
          end)
        end)

      assert Automerge.get_document(s1) == %{"list" => ["zero", 2, %{"subobject" => "value"}]}
    end

    # FIXME(ts): Add test case for pop
  end

  describe "pop_in" do
    setup do
      s1 = Automerge.from!(%{"list" => Automerge.list([1, 2, %{"subobject" => "value"}])})

      [s1: s1]
    end

    test "can delete an existing list index", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["list"][0])

          doc
        end)

      assert Automerge.get_document(s1) == %{"list" => [2, %{"subobject" => "value"}]}
    end

    test "gets an error when deleting a non-existing index", %{s1: s1} do
      assert_raise RuntimeError, ~r/are out of bounds for list/, fn ->
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["list"][16])

          doc
        end)
      end
    end
  end

  ## Automerge.List functions

  describe "first/1" do
    test "works on an empty list" do
      s1 = Automerge.from!(%{"list" => Automerge.list()})

      assert Automerge.List.first(s1["list"]) == nil
    end

    test "works with a list with a few items" do
      s1 = Automerge.from!(%{"list" => Automerge.list([1, 2, 3])})

      assert Automerge.List.first(s1["list"]) == 1
    end
  end

  describe "last/1" do
    test "works on an empty list" do
      s1 = Automerge.from!(%{"list" => Automerge.list()})

      assert Automerge.List.last(s1["list"]) == nil
    end

    test "works with a list with a few items" do
      s1 = Automerge.from!(%{"list" => Automerge.list([1, 2, 3])})

      assert Automerge.List.last(s1["list"]) == 3
    end
  end

  describe "insert_at/1" do
    test "works on an empty list" do
      doc = Automerge.from!(%{"list" => Automerge.list()})

      {doc, _change} =
        Automerge.change!(doc, fn doc ->
          Automerge.List.insert_at(doc["list"], 0, "first")
        end)

      assert Automerge.get_document(doc) == %{"list" => ["first"]}
    end

    test "inserting out of bounds (upper) recieves an error" do
      assert_raise RuntimeError, ~r/out of bounds for list/, fn ->
        Automerge.change!(Automerge.from!(%{"list" => Automerge.list()}), fn doc ->
          update_in(doc["list"], &Automerge.List.insert_at(&1, 100, "first"))
        end)
      end
    end

    test "inserting out of bounds (lower) receives an error" do
      assert_raise RuntimeError, ~r/out of bounds for list/, fn ->
        Automerge.change!(Automerge.from!(%{"list" => Automerge.list()}), fn doc ->
          update_in(doc["list"], &Automerge.List.insert_at(&1, -1, "first"))
        end)
      end
    end
  end

  describe "delete_at/1" do
    test "works on a simple list" do
      doc = Automerge.from!(%{"list" => Automerge.list(["a", "b", "c", "d", "e"])})

      {doc, _change} =
        Automerge.change!(doc, fn doc ->
          Automerge.List.delete_at(doc["list"], 2)
        end)

      assert Automerge.get_document(doc) == %{"list" => ["first"]}
    end

    test "inserting out of bounds (upper) recieves an error" do
      assert_raise RuntimeError, ~r/out of bounds for list/, fn ->
        Automerge.change!(Automerge.from!(%{"list" => Automerge.list()}), fn doc ->
          update_in(doc["list"], &Automerge.List.delete_at(&1, 100))
        end)
      end
    end

    test "inserting out of bounds (lower) receives an error" do
      assert_raise RuntimeError, ~r/out of bounds for list/, fn ->
        Automerge.change!(Automerge.from!(%{"list" => Automerge.list()}), fn doc ->
          update_in(doc["list"], &Automerge.List.delete_at(&1, -1))
        end)
      end
    end
  end

  describe "replace_at/1" do
  end

  describe "update_at/1" do
  end

  describe "append/1" do
  end

  describe "prepend/1" do
  end

  describe "splice/1" do
  end


  ## From

  describe "from" do
    test "can create a simple list" do
      s1 =
        Automerge.from!(%{"list" => Automerge.list([1, 2, 3, "a", "b", "c"])})

      assert is_struct(s1["list"], Automerge.List)

      assert Automerge.get_document(s1) == %{
               "list" => [1, 2, 3, "a", "b", "c"]
             }
    end

    test "[]" do
      s1 =
        Automerge.from!(%{"list" => []})
    end
  end


  describe "simple lists" do
  end

  describe "nested lists" do
    test "inspecting nested lists" do
      _doc =
        Automerge.from!(%{
          "list" =>
            Automerge.list([Automerge.list(Enum.to_list(0..2)), Automerge.list(["a", "b", "c"])])
        })
    end

    test "enumerate over lists" do
      doc =
        Automerge.from!(%{
          "list" =>
            Automerge.list([Automerge.list(Enum.to_list(0..2)), Automerge.list(["a", "b", "c"])])
        })

      for l <- doc["list"] do
        IO.inspect(l, label: :inside_list)
      end

      #
      #      {doc, change} = Automerge.change!(doc, fn doc ->
      #
      #
      #      end)

      IO.inspect(doc)
    end
  end

  test "lengthy lists keep order" do
    doc = Automerge.from!(%{"list" => Automerge.list([Enum.to_list(0..100)])})

    assert Automerge.get_document(doc) == %{"list" => Enum.to_list(0..100)}
  end

  test "lengthy lists can be accurately operated on" do
    doc = Automerge.from!(%{"list" => Automerge.list([Enum.to_list(0..100)])})

    {doc, _patch} =
      Automerge.change!(doc, fn doc ->
        update_in(doc["list"], fn list -> Automerge.List.delete_at(list, 25, 25) end)
      end)

    assert Automerge.get_document(doc) == %{"list" => Enum.to_list(0..100)}
  end

  test "complex operations" do
    doc = Automerge.from!(%{"list" => Automerge.list([0, 1, 2, "a", "b", "c"])})

    {doc, _change} =
      Automerge.change!(doc, fn doc ->
        update_in(doc["list"], fn list ->
          list
          |> Automerge.List.slice(1..2)
          |> Automerge.List.append(["d", "e", "f", "g"])
          |> Automerge.List.delete_at(1)
          |> Automerge.List.insert_at(3, ["foo", "bar"])
          |> Automerge.List.first()
        end)
      end)
  end

  #  test "recursion bug" do
  #    {s1, _change} =
  #      Automerge.change!(Automerge.init(), &put_in(&1["noodles"], Automerge.list(["udon", "ramen", "soba"])))
  #
  #    {s1, _change} =
  #      Automerge.change!(s1, fn doc ->
  #        update_in(doc, ["noodles"], fn elem ->
  #         {elem, Automerge.List.delete_at(elem, 1)}
  #        end)
  #      end)
  #  end
end
