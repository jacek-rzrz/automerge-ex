defmodule Automerge.MapTest do
  use Automerge.HelperCase, async: true

  ## Elixir Map's effects on the data structure

  describe "Enum.Map on doc root" do
    test "Map.put/3" do
      {doc, _change} =
        Automerge.change!(Automerge.init(), fn doc ->
          Map.put(doc, "foo", "bar")
        end)

      assert Automerge.get_document(doc) == %{"foo" => "bar"}
    end

    test "Map.merge/1" do
      {doc, _change} =
        Automerge.change!(Automerge.init(), fn doc ->
          Map.merge(doc, %{"foo" => "bar"})
        end)

      assert Automerge.get_document(doc) == %{"foo" => "bar"}
    end

    test "Map.delete/2" do
      doc = Automerge.from!(%{"foo" => "bar"})

      # Sadly I don't think there is anything I can do to support this or error out.
      {doc, _change} =
        Automerge.change!(doc, fn doc ->
          Map.delete(doc, "foo")
        end)

      assert Automerge.get_document(doc) == %{"foo" => "bar"}
    end
  end

  describe "Enum.map in nested objects" do
    setup do
      s1 = Automerge.from!(%{"nested" => %{}})

      [s1: s1]
    end

    test "Map.put/3", %{s1: s1} do
      {doc, _change} =
        Automerge.change!(s1, fn doc ->
          Map.put(doc["nested"], "foo", "bar")
        end)

      assert Automerge.get_document(doc) == %{"nested" => %{"foo" => "bar"}}
    end

    test "Map.merge/3", %{s1: s1} do
      {doc, _change} =
        Automerge.change!(s1, fn doc ->
          Map.merge(doc["nested"], %{"foo" => "bar"})
        end)

      assert Automerge.get_document(doc) == %{"foo" => "bar"}
    end
  end

  ## Automerge.Map's Enumerable protocol

  describe "enumerable count" do
    test "empty map" do
      doc = Automerge.from!(%{"map" => %{}})

      assert Enum.count(doc["map"]) === 0
    end

    test "map with small amount of elements" do
      doc = Automerge.from!(%{"map" => %{"one" => 1, "two" => 2, "three" => 3}})

      assert Enum.count(doc["map"]) === 3
    end
  end

  ## Automerge.Map's Access Behaviour

  describe "get_in" do
    setup do
      s1 = Automerge.from!(%{"person1" => %{"favouriteBird" => "hawk"}})

      [s1: s1]
    end

    test "opaque from the outside", %{s1: s1} do
      person1 = s1["person1"]

      # Despite us attempting to go into the object it should return the parent. This behaviour is
      # so Automerge.get_object_id/1 works as expected.
      assert person1 == get_in(person1, ["favouriteBird"])
    end
  end

  describe "get_and_update" do
    setup do
      s1 = Automerge.from!(%{"person1" => %{"favouriteBird" => "hawk"}})

      [s1: s1]
    end

    test "blows up when outside a change fn", %{s1: s1} do
      assert_raise RuntimeError,
                   "Can only modify the document inside of change!/2 or change!/3 callback",
                   fn ->
                     get_and_update_in(s1["person1"], fn person1 ->
                       put_in(person1["favouriteCandy"], "Snickers")
                     end)
                   end
    end

    test "allow for updating when it's invoked inside a change fn", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["person1"], fn person1 ->
            put_in(person1["favouriteCandy"], "Snickers")
          end)
        end)

      assert Automerge.get_document(s1) == %{
               "person1" => %{"favouriteBird" => "hawk", "favouriteCandy" => "Snickers"}
             }
    end

    # FIXME(ts): Add test case for pop
  end

  describe "pop_in" do
    test "deleting an existing map property" do
      s1 = Automerge.from!(%{"config" => %{"background" => "blue", "logo_url" => "logo.png"}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {prev, doc} = pop_in(doc["config"]["logo_url"])

          assert prev == "logo.png"
          doc
        end)

      assert Automerge.get_document(s1) == %{"config" => %{"background" => "blue"}}
    end

    test "deleting non-existing map property" do
      s1 = Automerge.from!(%{"config" => %{"background" => "blue", "logo_url" => "logo.png"}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["config"]["unicorn"])

          doc
        end)

      assert Automerge.get_document(s1) == %{
               "config" => %{"background" => "blue", "logo_url" => "logo.png"}
             }
    end

    test "deleting a nested map property" do
      s1 = Automerge.from!(%{"l1" => %{"l2" => %{"l3" => "hello"}}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["l1"]["l2"])

          doc
        end)

      assert Automerge.get_document(s1) == %{"l1" => %{}}
    end
  end

  ## Automerge.Map functions

  describe "put/3" do
    test "can put a value" do
      s1 = Automerge.from!(%{"config" => %{"background" => "blue"}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["config"], fn config ->
            Automerge.Map.put(config, "logo_url", "logo.png")
          end)
        end)

      assert Automerge.get_document(s1) == %{
               "config" => %{"background" => "blue", "logo_url" => "logo.png"}
             }
    end

    test "numeric keys are disallowed" do
      s1 = Automerge.from!(%{"map" => %{"background" => "blue"}})

      assert_raise RuntimeError, ~r/Numeric keys are unsupported as keys/, fn ->
        Automerge.change!(s1, fn doc ->
          update_in(doc["map"], fn map ->
            Automerge.Map.put(map, 0, "start")
          end)
        end)
      end
    end
  end

  describe "merge/2" do
  end

  describe "delete/2" do
    test "can put a value" do
      s1 = Automerge.from!(%{"config" => %{"background" => "blue", "logo_url" => "logo.png"}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["config"], fn config ->
            Automerge.Map.delete(config, "logo_url")
          end)
        end)

      assert Automerge.get_document(s1) == %{"config" => %{"background" => "blue"}}
    end

    test "can delete a non-existing map property" do
      s1 = Automerge.from!(%{"config" => %{"background" => "blue", "logo_url" => "logo.png"}})

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["config"], fn config ->
            Automerge.Map.delete(config, "unicorn")
          end)
        end)

      assert Automerge.get_document(s1) == %{
               "config" => %{"background" => "blue", "logo_url" => "logo.png"}
             }
    end
  end

  ## Inner context changes (where ops are not propagated to the doc as they maybe ephemeral)

  ## From

  describe "from" do
    test "simple Elixir maps with many keys and variety of values" do
      s1 =
        Automerge.from!(%{
          "map" => %{
            "key" => "val",
            "text" => Automerge.text(),
            "list" => Automerge.list(),
            "number" => 1
          }
        })

      assert is_struct(s1["map"], Automerge.Map)

      assert Automerge.get_document(s1) == %{
               "map" => %{
                 "key" => "val",
                 "list" => [],
                 "number" => 1,
                 "text" => []
               }
             }
    end

    test "nested elixir maps are translated" do
      s1 = Automerge.from!(%{"l0" => %{"l1" => %{"l2" => %{"l3" => "hello"}}}})

      assert is_struct(get_in(s1, ["l0"]), Automerge.Map)
      assert is_struct(get_in(s1, ["l0", "l1"]), Automerge.Map)
      assert get_in(s1, ["l0"]) !== get_in(s1, ["l0", "l1"])

      assert is_struct(get_in(s1, ["l0", "l1", "l2"]), Automerge.Map)
      assert get_in(s1, ["l0", "l1"]) !== get_in(s1, ["l0", "l1", "l2"])

      assert is_struct(get_in(s1, ["l0", "l1", "l2", "l3"]), Automerge.Map)

      # Last should be the same object as l3 is a field on l2
      assert get_in(s1, ["l0", "l1", "l2"]) === get_in(s1, ["l0", "l1", "l2", "l3"])
    end
  end

  ## Validation

  test "Unsupported Elixir types are caught as invalid map values" do
    s1 = Automerge.from!(%{"nested" => %{}})

    assert_raise RuntimeError, "Unsupported type of value: :atom", fn ->
      Automerge.change!(s1, fn doc ->
        update_in(doc["nested"], fn nested ->
          put_in(nested["atom"], :atom)
        end)
      end)
    end

    assert_raise RuntimeError, "Unsupported type of value: :atom", fn ->
      Automerge.change!(s1, fn doc ->
        update_in(doc["nested"], fn nested ->
          Automerge.Map.put(nested, "atom", :atom)
        end)
      end)
    end
  end
end
