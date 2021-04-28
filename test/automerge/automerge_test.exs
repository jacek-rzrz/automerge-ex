defmodule AutomergeTest do
  use ExUnit.Case, async: true
  doctest Automerge

  alias Automerge.Backend.NIF, as: Backend

  describe "initialization" do
    test "should initially be an empty map" do
      doc = Automerge.init()

      assert Automerge.get_document(doc) == %{}
    end

    test "should allow instantiating from an existing object" do
      initial_state = %{"birds" => %{"wrens" => 3, "magpies" => 4}}
      doc = Automerge.from!(initial_state)

      assert Automerge.get_document(doc) == initial_state
    end

    test "should allow merging of an object initialized with `from`" do
      doc1 = Automerge.from!(%{"cards" => Automerge.list()})
      doc2 = Automerge.merge!(Automerge.init(), doc1)

      assert Automerge.get_document(doc2) == %{"cards" => []}
    end

    test "should allow passing an actorId when instantiating from an existing object" do
      actor_id = "1234"
      doc = Automerge.from!(%{"foo" => 1}, actor_id: actor_id)

      assert Automerge.get_actor_id(doc) == actor_id
    end

    test "accepts an empty object as initial state" do
      doc = Automerge.from!(%{})

      assert Automerge.get_document(doc) == %{}
    end

    test "accepts an array as initial state, but converts it to an object" do
      doc = Automerge.from!(["a", "b", "c"])

      assert Automerge.get_document(doc) == %{"0" => "a", "1" => "b", "2" => "c"}
    end

    test "accepts strings as initial values, but treats them as an array of characters" do
      doc = Automerge.from!("abc")

      assert Automerge.get_document(doc) == %{"0" => "a", "1" => "b", "2" => "c"}
    end

    test "ignores numbers provided as initial values" do
      doc = Automerge.from!(123)

      assert Automerge.get_document(doc) == %{}
    end

    test "ignores booleans provided as initial values" do
      doc1 = Automerge.from!(false)

      assert Automerge.get_document(doc1) == %{}

      doc2 = Automerge.from!(true)

      assert Automerge.get_document(doc2) == %{}
    end
  end

  test "changes should be retrievable" do
    s1 = Automerge.init()
    change1 = Automerge.get_last_local_change(s1)

    {s2, _change} = Automerge.change!(s1, &put_in(&1["foo"], "bar"))
    change2 = Automerge.get_last_local_change(s2)

    assert change1 == nil

    change = Backend.decode_change(change2)

    assert change == %{
             "actor" => change["actor"],
             "deps" => [],
             "seq" => 1,
             "startOp" => 1,
             "hash" => change["hash"],
             "message" => nil,
             "time" => change["time"],
             "ops" => [
               %{
                 "obj" => "_root",
                 "key" => "foo",
                 "action" => "set",
                 "value" => "bar",
                 "pred" => []
               }
             ]
           }
  end

  test "should not register any conflicts on repeated assignment" do
    s1 = Automerge.init()
    assert Automerge.get_conflicts(s1, ["foo"]) == nil

    {s1, _change} = Automerge.change!(s1, &put_in(&1["foo"], "one"))
    assert Automerge.get_conflicts(s1, ["foo"]) == nil

    {s1, _change} = Automerge.change!(s1, &put_in(&1["foo"], "two"))

    assert Automerge.get_conflicts(s1, ["foo"]) == nil
  end

  #  s1 = Automerge.change(s1, doc => doc.nesting = {
  #          maps: { m1: { m2: { foo: "bar", baz: {} }, m2a: { } } },
  #          lists: [ [ 1,2,3 ] , [ [ 3,4,5,[6]], 7 ] ],
  #          mapsinlists: [ { foo: "bar" } , [ { bar: "baz" } ] ],
  #          listsinmaps: { foo: [1,2,3], bar: [ [ { baz: "123" } ] ] }
  #        })
  #        s1 = Automerge.change(s1, doc => {
  #          doc.nesting.maps.m1a = "123"
  #          doc.nesting.maps.m1.m2.baz.xxx = "123"
  #          delete doc.nesting.maps.m1.m2a
  #          doc.nesting.lists.shift()
  #          doc.nesting.lists[0][0].pop()
  #          doc.nesting.lists[0][0].push(100)
  #          doc.nesting.mapsinlists[0].foo = "baz"
  #          doc.nesting.mapsinlists[1][0].foo = "bar"
  #          delete doc.nesting.mapsinlists[1]
  #          doc.nesting.listsinmaps.foo.push(4)
  #          doc.nesting.listsinmaps.bar[0][0].baz = "456"
  #          delete doc.nesting.listsinmaps.bar
  #        })
  #        assert.deepStrictEqual(s1, { nesting: {
  #          maps: { m1: { m2: { foo: "bar", baz: { xxx: "123" } } }, m1a: "123" },
  #          lists: [ [ [ 3,4,5,100 ], 7 ] ],
  #          mapsinlists: [ { foo: "baz" } ],
  #          listsinmaps: { foo: [1,2,3,4] }
  #        }})

  test "should handle deep nesting" do
    s1 = Automerge.init()

    {s1, _change} =
      Automerge.change!(s1, fn doc ->
        {_, doc} =
          get_and_update_in(doc["nesting"], fn nesting ->
            doc =
              nesting
              |> put_in(["maps"], %{
                "m1" => %{"m2" => %{"foo" => "bar", "baz" => %{}}, "m2a" => %{}}
              })
              |> put_in(
                ["lists"],
                Automerge.list([
                  Automerge.list([1, 2, 3]),
                  Automerge.list([Automerge.list([3, 4, 5, Automerge.list([6])]), 7])
                ])
              )
              |> put_in(
                ["mapsinlists"],
                Automerge.list([
                  %{"foo" => "bar"},
                  Automerge.list([Automerge.list([%{"bar" => "baz"}])])
                ])
              )
              |> put_in(["listsinmaps"], %{
                "foo" => Automerge.list([1, 2, 3]),
                "bar" => Automerge.list([Automerge.list([%{"bar" => "123"}])])
              })

            {nesting, doc}
          end)

        doc
      end)

    {s1, _change} =
      Automerge.change!(s1, fn doc ->
        put_in(doc["nesting"]["maps"]["m1"]["m2"]["baz"]["xxx"], "123")
      end)

    Automerge.get_document(s1)
  end

  describe "sequential use changes" do
    setup do
      [s1: Automerge.init()]
    end

    test "should group several changes", %{s1: s1} do
      {s2, _change} =
        Automerge.change!(s1, "change message", fn doc ->
          doc = put_in(doc["first"], "one")

          assert doc["first"] == "one"

          doc = put_in(doc["second"], "two")

          assert doc["second"] == "two"

          doc
        end)

      assert Automerge.get_document(s1) === %{}
      assert Automerge.get_document(s2) === %{"first" => "one", "second" => "two"}
    end

    test "should allow repeated reading and writing of values", %{s1: s1} do
      {s2, _change} =
        Automerge.change!(s1, "change message", fn doc ->
          doc = put_in(doc["value"], "a")

          assert doc["value"] == "a"

          doc = put_in(doc["value"], "b")
          doc = put_in(doc["value"], "c")

          assert doc["value"] == "c"

          doc
        end)

      assert Automerge.get_document(s1) === %{}
      assert Automerge.get_document(s2) === %{"value" => "c"}
    end

    test "should not record conflicts when writing the same field several times within one change",
         %{s1: s1} do
      {s2, _change} =
        Automerge.change!(s1, "change message", fn doc ->
          doc
          |> put_in(["value"], "a")
          |> put_in(["value"], "b")
          |> put_in(["value"], "c")
        end)

      assert Automerge.get_document(s2) === %{"value" => "c"}
      assert Automerge.get_conflicts(s2, ["value"]) === nil
    end

    test "should return the unchanged state object if nothing change", %{s1: s1} do
      {s2, _change} = Automerge.change!(s1, & &1)

      assert s1 === s2
    end

    test "should ignore field updates that write the existing value", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], 123))
      {s2, _change} = Automerge.change!(s1, &put_in(&1["field"], 123))

      assert s2 === s1
    end

    test "should not ignore field updates that resolve a conflict", %{s1: s1} do
      s2 = Automerge.merge!(Automerge.init(), s1)
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], 123))
      {s2, _change} = Automerge.change!(s2, &put_in(&1["field"], 321))
      s1 = Automerge.merge!(s1, s2)

      s1doc = Automerge.get_document(s1)

      assert Automerge.get_conflicts(s1, ["field"]) |> Map.keys() |> Enum.count() == 2

      {resolved, _change} =
        Automerge.change!(s1, &update_in(&1["field"], fn field -> {field, s1doc["field"]} end))

      assert resolved !== s1
      assert Automerge.get_document(resolved) == %{"field" => s1doc["field"]}
      assert Automerge.get_conflicts(resolved, ["field"]) == nil
    end

    test "should ignore list element updates that write the existing value", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1, ["list"], Automerge.list([123])))

      {s2, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["list"][0], fn _number -> 123 end)
        end)

      assert Automerge.get_document(s2) === Automerge.get_document(s1)
    end
  end

  describe "sequential use empty_change!" do
    setup do
      [s1: Automerge.init()]
    end

    test "should append an empty change to the history", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, "first change", &Map.put(&1, "field", 123))
      s2 = Automerge.empty_change(s1, "empty change")

      assert s1 !== s2
      assert Automerge.get_document(s2) === Automerge.get_document(s1)

      assert s2
             |> Automerge.get_history()
             |> Enum.map(&Automerge.History.get_change!/1)
             |> get_in([Access.all(), "message"]) == [
               "first change",
               "empty change"
             ]
    end

    test "should reference dependencies", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], 123))
      s2 = Automerge.merge!(Automerge.init(), s1)
      {s2, _change} = Automerge.change!(s2, &put_in(&1["other"], "hello"))
      s1 = Automerge.empty_change(Automerge.merge!(s1, s2))

      history_changes = Automerge.get_history(s1) |> Enum.map(&Automerge.History.get_change!/1)
      empty_change = get_in(history_changes, [Access.at(2)])

      assert empty_change["deps"] == [
               get_in(history_changes, [Access.at(0), "hash"]),
               get_in(history_changes, [Access.at(1), "hash"])
             ]

      assert empty_change["ops"] == []
    end
  end

  describe "sequential use root object" do
    setup do
      [s1: Automerge.init()]
    end

    test "should handle single-property assignment", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, "set bar", &Map.put(&1, "foo", "bar"))
      {s1, _change} = Automerge.change!(s1, "set zap", &Map.put(&1, "zip", "zap"))

      assert Automerge.get_document(s1)["foo"] == "bar"
      assert Automerge.get_document(s1)["zip"] == "zap"

      assert Automerge.get_document(s1) == %{"foo" => "bar", "zip" => "zap"}
    end

    test "should allow floating-point values", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &Map.put(&1, "number", 1_589_032_171.1))

      assert Automerge.get_document(s1)["number"] == 1_589_032_171.1
    end

    test "should handle multi-property assignment", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, "multi-assign", &Map.merge(&1, %{"foo" => "bar", "answer" => 42}))

      assert Automerge.get_document(s1)["foo"] == "bar"
      assert Automerge.get_document(s1)["answer"] == 42
      assert Automerge.get_document(s1) == %{"foo" => "bar", "answer" => 42}
    end

    test "should handle root property deletion", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, "multi-assign", &Map.merge(&1, %{"foo" => "bar", "answer" => 42}))

      assert Automerge.get_document(s1)["foo"] == "bar"
      assert Automerge.get_document(s1)["answer"] == 42
      assert Automerge.get_document(s1) == %{"foo" => "bar", "answer" => 42}
    end

    test "should follow JS delete behavior" do
      # TODO(ts): Implement?
    end

    test "should allow the type of a property to be changed", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, "set number", &Map.put(&1, "prop", 123))
      assert Automerge.get_document(s1)["prop"] == 123

      {s1, _change} = Automerge.change!(s1, "set string", &Map.put(&1, "prop", "123"))
      assert Automerge.get_document(s1)["prop"] == "123"

      {s1, _change} = Automerge.change!(s1, "set null", &Map.put(&1, "prop", nil))
      assert Automerge.get_document(s1)["prop"] == nil

      {s1, _change} = Automerge.change!(s1, "set bool", &Map.put(&1, "prop", true))
      assert Automerge.get_document(s1)["prop"] == true
    end

    test "should require property names to be valid", %{s1: s1} do
      assert_raise RuntimeError, "The key of a map entry must not be an empty string", fn ->
        Automerge.change!(s1, &Map.put(&1, "", "x"))
      end
    end

    test "should not allow assignment of unsupported datatypes", %{s1: s1} do
      # Functions
      assert_raise RuntimeError, ~r/Unsupported type of value: #Function/, fn ->
        Automerge.change!(s1, &put_in(&1["foo"], fn -> nil end))
      end

      # Atoms
      assert_raise RuntimeError, ~r/Unsupported type of value: :/, fn ->
        Automerge.change!(s1, &put_in(&1["foo"], :atom))
      end

      # PIDs
      assert_raise RuntimeError, ~r/Unsupported type of value: #PID/, fn ->
        Automerge.change!(s1, &put_in(&1["foo"], self()))
      end

      # Tuples
      assert_raise RuntimeError, ~r/Unsupported type of value: {/, fn ->
        Automerge.change!(s1, &put_in(&1["foo"], {"this"}))
      end
    end
  end

  describe "sequential use nested maps" do
    setup do
      [s1: Automerge.init()]
    end

    test "should assign an objectId to nested maps", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["nested"], %{}))
      assert Automerge.get_object_id(s1["nested"]) !== "_root"

      assert Regex.match?(~r/^[0-9]+@[0-9a-f]{32}$/, Automerge.get_object_id(s1["nested"])) ==
               true
    end

    test "should handle assignment of a nested property", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, "first change", fn doc ->
          doc
          |> put_in(["nested"], %{})
          |> put_in(["nested", "foo"], "bar")
        end)

      {s1, _change} =
        Automerge.change!(s1, "second change", fn doc ->
          update_in(doc["nested"]["one"], fn _number -> 1 end)
        end)

      assert Automerge.get_document(s1) == %{"nested" => %{"foo" => "bar", "one" => 1}}
    end

    test "should handle assignment of an object literal", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["textStyle"], %{"bold" => false, "fontSize" => 12}))

      assert Automerge.get_document(s1) === %{"textStyle" => %{"bold" => false, "fontSize" => 12}}
    end

    test "should handle assignment of multiple nested properties", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          doc
          |> put_in(["textStyle"], %{"bold" => false, "fontSize" => 12})
          |> update_in(["textStyle"], fn text_style ->
            text_style
            |> put_in(["typeface"], "Optima")
            |> put_in(["fontSize"], 14)
          end)
        end)

      assert Automerge.get_document(s1) === %{
               "textStyle" => %{"bold" => false, "fontSize" => 14, "typeface" => "Optima"}
             }
    end

    test "should handle arbitrary-depth nesting", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1, ~w(a b c d e f g), "h"))

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = get_and_update_in(doc, ~w(a b c d e f i), fn value -> {value, "j"} end)

          doc
        end)

      assert Automerge.get_document(s1) == %{
               "a" => %{"b" => %{"c" => %{"d" => %{"e" => %{"f" => %{"g" => "h", "i" => "j"}}}}}}
             }
    end

    test "should allow an old object to be replaced with a new one", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          "change 1",
          &put_in(&1["myPet"], %{"species" => "dog", "legs" => 4, "breed" => "dachshund"})
        )

      {s2, _change} =
        Automerge.change!(s1, "change 1", fn doc ->
          put_in(
            doc["myPet"],
            %{
              "species" => "koi",
              "variety" => "紅白",
              "colors" => %{"red" => true, "white" => true, "black" => false}
            }
          )
        end)

      assert Automerge.get_document(s1)["myPet"] == %{
               "species" => "dog",
               "legs" => 4,
               "breed" => "dachshund"
             }

      assert Automerge.get_document(s2)["myPet"] === %{
               "species" => "koi",
               "variety" => "紅白",
               "colors" => %{"red" => true, "white" => true, "black" => false}
             }
    end

    test "should allow fields to be changed between primitive and nested map", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["color"], "#ff7f00"))
      assert Automerge.get_document(s1)["color"] === "#ff7f00"

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          put_in(doc["color"], %{"red" => 255, "green" => 127, "blue" => 0})
        end)

      assert Automerge.get_document(s1)["color"] === %{"red" => 255, "green" => 127, "blue" => 0}

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["color"], fn _prev -> "#ff7f00" end)
        end)

      assert Automerge.get_document(s1)["color"] === "#ff7f00"
    end

    test "should not allow several references to the same map object", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["object"], %{}))

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       put_in(doc["x"], doc["object"])
                     end)
                   end

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       put_in(doc["x"], s1["object"])
                     end)
                   end

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       doc = put_in(doc["x"], %{})

                       put_in(doc["y"], doc["x"])
                     end)
                   end
    end

    test "should handle deletion of properties within a map", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          "set style",
          &Map.merge(&1, %{
            "title" => "Hello",
            "textStyle" => %{"typeface" => "Optima", "bold" => false, "fontSize" => 12}
          })
        )

      {s1, _change} =
        Automerge.change!(s1, "non-bold", fn doc ->
          {_prev, doc} = pop_in(doc["textStyle"])

          doc
        end)

      assert Automerge.get_document(s1)["title"] == "Hello"
    end

    test "should handle deletion of references to a map", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          "set style",
          &put_in(&1["textStyle"], %{"typeface" => "Optima", "bold" => false, "fontSize" => 12})
        )

      {s1, _change} =
        Automerge.change!(s1, "non-bold", fn doc ->
          {_, doc} = pop_in(doc["textStyle"]["bold"])

          doc
        end)

      assert Automerge.get_document(s1)["textStyle"] == %{
               "typeface" => "Optima",
               "fontSize" => 12
             }
    end

    test "should validate field names", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["nested"], %{}))

      assert_raise RuntimeError, ~r/The key of a map entry must not be an empty string/, fn ->
        Automerge.change!(s1, fn doc ->
          put_in(doc["nested"][""], "x")
        end)
      end

      assert_raise RuntimeError, ~r/The key of a map entry must not be an empty string/, fn ->
        Automerge.change!(s1, fn doc ->
          put_in(doc["nested"], %{"" => "x"})
        end)
      end
    end
  end

  describe "sequential use lists" do
    setup do
      [s1: Automerge.init()]
    end

    test "should allow elements to be inserted", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          put_in(doc["noodles"], Automerge.list())
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["noodles"], fn noodles ->
            Automerge.List.append(noodles, ["udon", "soba"])
          end)
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["noodles"], fn noodles ->
            Automerge.List.insert_at(noodles, 1, "ramen")
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == ["udon", "ramen", "soba"]
    end

    test "should handle assignment of a list literal", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["noodles"], Automerge.list(["udon", "ramen", "soba"]))
        )

      assert Automerge.get_document(s1)["noodles"] == ["udon", "ramen", "soba"]
    end

    test "should allow for numeric indexes", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["noodles"], Automerge.list(["udon", "ramen", "soba"]))
        )

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles", 1], fn _ramen ->
            "Ramen!"
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == ["udon", "Ramen!", "soba"]
    end

    test "should handle deletion of list elements", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["noodles"], Automerge.list(["udon", "ramen", "soba"])))

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles"], fn elem ->
            Automerge.List.delete_at(elem, 1)
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == ["udon", "soba"]
    end

    test "should handle assignment of individual list indexes", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["japaneseFood"], Automerge.list(["udon", "ramen", "soba"]))
        )

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["japaneseFood"], fn elem ->
            Automerge.List.replace_at(elem, 1, "sushi")
          end)
        end)

      assert Automerge.get_document(s1)["japaneseFood"] == ["udon", "sushi", "soba"]
    end

    test "should treat out-by-one assignment as insertion", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["japaneseFood"], Automerge.list(["udon"])))

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["japaneseFood"], fn elem ->
            Automerge.List.append(elem, ["sushi"])
          end)
        end)

      assert Automerge.get_document(s1)["japaneseFood"] == ["udon", "sushi"]
    end

    test "should not allow out-of-range assignment"

    test "should allow bulk assignment of multiple list indexes"

    test "should handle nested objects", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(
            &1["noodles"],
            Automerge.list([
              %{"type" => "ramen", "dishes" => Automerge.list(["tonkotsu", "shoyu"])}
            ])
          )
        )

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles"], fn elem ->
            Automerge.List.append(elem, [
              %{"type" => "udon", "dishes" => Automerge.list(["tempura udon"])}
            ])
          end)
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles", 0, "dishes"], fn dishes ->
            Automerge.List.append(dishes, "miso")
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == [
               %{"type" => "ramen", "dishes" => ["tonkotsu", "shoyu", "miso"]},
               %{"type" => "udon", "dishes" => ["tempura udon"]}
             ]
    end

    test "should handle nested lists", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(
            &1["noodleMatrix"],
            Automerge.list([Automerge.list(["ramen", "tonkotsu", "shoyu"])])
          )
        )

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["noodleMatrix"], fn matrix ->
            Automerge.List.append(matrix, Automerge.list(["udon", "tempura udon"]))
          end)
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["noodleMatrix"][0], fn matrix ->
            Automerge.List.append(matrix, ["miso"])
          end)
        end)

      assert Enum.at(Automerge.get_document(s1)["noodleMatrix"], 0) == [
               "ramen",
               "tonkotsu",
               "shoyu",
               "miso"
             ]

      assert Enum.at(Automerge.get_document(s1)["noodleMatrix"], 1) == ["udon", "tempura udon"]
    end

    test "should handle replacement of the entire list", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["noodles"], Automerge.list(["udon", "soba", "ramen"])))

      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["japaneseNoodles"], Automerge.list(["udon", "soba", "ramen"]))
        )

      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["noodles"], Automerge.list(["wonton", "pho"])))

      assert Automerge.get_document(s1) == %{
               "noodles" => ["wonton", "pho"],
               "japaneseNoodles" => ["udon", "soba", "ramen"]
             }
    end

    test "should allow assignment to change the type of a list element", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["noodles"], Automerge.list(["udon", "soba", "ramen"])))

      assert Automerge.get_document(s1)["noodles"] == ["udon", "soba", "ramen"]

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles", 1], fn _noodle ->
            %{"type" => "soba", "options" => Automerge.list(["hot", "cold"])}
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == [
               "udon",
               %{"type" => "soba", "options" => ["hot", "cold"]},
               "ramen"
             ]

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles"], fn noodles ->
            Automerge.List.replace_at(noodles, 1, Automerge.list(["hot soba", "cold soba"]))
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == ["udon", ["hot soba", "cold soba"], "ramen"]

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["noodles"], fn noodles ->
            Automerge.List.replace_at(noodles, 1, "soba is the best")
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == ["udon", "soba is the best", "ramen"]
    end

    test "should allow list creation and assignment in the same change callback", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          doc
          |> put_in(["letters"], Automerge.list(["a", "b", "c"]))
          |> put_in(["letters", 1], "d")
        end)

      assert Automerge.get_document(s1)["letters"] == ["a", "d", "c"]
    end

    test "should allow adding and removing list elements in the same change callback", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["noodles"], Automerge.list()))

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          doc
          |> update_in(["noodles"], fn noodles -> Automerge.List.append(noodles, "udon") end)
          |> update_in(["noodles"], fn noodles ->
            Automerge.List.delete_at(noodles, 0)
          end)
        end)

      assert Automerge.get_document(s1)["noodles"] == []

      # Intentionally do it again to match the JS test.

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          doc
          |> update_in(["noodles"], fn noodles -> Automerge.List.append(noodles, "udon") end)
          |> update_in(["noodles"], fn noodles -> Automerge.List.delete_at(noodles, 0) end)
        end)

      assert Automerge.get_document(s1)["noodles"] == []
    end

    test "should handle arbitrary-depth nesting", %{s1: s1} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(
            &1["maze"],
            Automerge.list(
              Automerge.list(
                Automerge.list(
                  Automerge.list(
                    Automerge.list(
                      Automerge.list(
                        Automerge.list(Automerge.list(["noodles", Automerge.list(["here"])]))
                      )
                    )
                  )
                )
              )
            )
          )
        )

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["maze"][0][0][0][0][0][0][0][1], fn maze ->
            Automerge.List.prepend(maze, "found")
          end)
        end)

      assert Automerge.get_document(s1)["maze"] == [[[[[[[["noodles", ["found", "here"]]]]]]]]]
    end

    test "should not allow several references to the same list object", %{s1: s1} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["list"], Automerge.list()))

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       put_in(doc["x"], doc["list"])
                     end)
                   end

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       put_in(doc["x"], s1["list"])
                     end)
                   end

      assert_raise RuntimeError,
                   ~r/Cannot create a reference to an existing document object/,
                   fn ->
                     Automerge.change!(s1, fn doc ->
                       doc = put_in(doc["x"], Automerge.list())
                       put_in(doc["y"], doc["x"])
                     end)
                   end
    end
  end

  describe "sequential counters" do
  end

  describe "concurrent use" do
    setup do
      [s1: Automerge.init(), s2: Automerge.init(), s3: Automerge.init()]
    end

    test "should merge concurrent updates of different properties", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["foo"], "bar"))
      {s2, _change} = Automerge.change!(s2, &put_in(&1["hello"], "world"))

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3) == %{"foo" => "bar", "hello" => "world"}
      assert Automerge.get_conflicts(s3, ["foo"]) == nil
      assert Automerge.get_conflicts(s3, ["hello"]) == nil
    end

    @tag :counter
    test "should add concurrent increments of the same property"

    @tag :counter
    test "should add increments only to the values they precede"

    test "should detect concurrent updates of the same field", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], "one"))
      {s2, _change} = Automerge.change!(s2, &put_in(&1["field"], "two"))

      s3 = Automerge.merge!(s1, s2)

      if Automerge.get_actor_id(s1) > Automerge.get_actor_id(s2) do
        assert Automerge.get_document(s3)["field"] == "one"
      else
        assert Automerge.get_document(s3)["field"] == "two"
      end

      assert Automerge.get_conflicts(s3, ["field"]) == %{
               "1@#{Automerge.get_actor_id(s1)}" => "one",
               "1@#{Automerge.get_actor_id(s2)}" => "two"
             }
    end

    test "should detect concurrent updates of the same list element", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["birds"], Automerge.list(["finch"])))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} = Automerge.change!(s1, &put_in(&1, ["birds", 0], "greenfinch"))
      {s2, _change} = Automerge.change!(s2, &put_in(&1, ["birds", 0], "goldfinch"))

      s3 = Automerge.merge!(s1, s2)

      if Automerge.get_actor_id(s1) > Automerge.get_actor_id(s2) do
        assert Automerge.get_document(s3)["birds"] == ["greenfinch"]
      else
        assert Automerge.get_document(s3)["birds"] == ["goldfinch"]
      end

      assert Automerge.get_conflicts(s3, ["birds", 0]) == %{
               "3@#{Automerge.get_actor_id(s1)}" => "greenfinch",
               "3@#{Automerge.get_actor_id(s2)}" => "goldfinch"
             }
    end

    test "should handle changes within a conflicting map field", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], "string"))
      {s2, _change} = Automerge.change!(s2, &put_in(&1["field"], %{}))

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["field"], fn field ->
            put_in(field["innerKey"], 42)
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["field"] in ["string", %{"innerKey" => 42}]

      assert Automerge.get_conflicts(s3, ["field"]) == %{
               "1@#{Automerge.get_actor_id(s1)}" => "string",
               "1@#{Automerge.get_actor_id(s2)}" => %{"innerKey" => 42}
             }
    end

    test "should handle changes within a conflicting list element", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["list"], Automerge.list(["hello"])))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["list"], fn list ->
            Automerge.List.replace_at(list, 0, %{"map1" => true})
          end)
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["list"][0], fn field ->
            put_in(field["key"], 1)
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc["list"][0], fn _field -> %{"map2" => true} end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc["list"][0], fn field ->
            put_in(field["key"], 2)
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      if Automerge.get_actor_id(s1) > Automerge.get_actor_id(s2) do
        assert Automerge.get_document(s3)["list"] == [%{"map1" => true, "key" => 1}]
      else
        assert Automerge.get_document(s3)["list"] == [%{"map2" => true, "key" => 2}]
      end

      assert Automerge.get_conflicts(s3, ["list", 0]) == %{
               "3@#{Automerge.get_actor_id(s1)}" => [%{"map1" => true, "key" => 1}],
               "3@#{Automerge.get_actor_id(s2)}" => [%{"map2" => true, "key" => 2}]
             }
    end

    test "should not merge concurrently assigned nested maps", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change1} = Automerge.change!(s1, &put_in(&1["config"], %{"background" => "blue"}))
      {s2, _change2} = Automerge.change!(s2, &put_in(&1["config"], %{"logo_url" => "logo.png"}))

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["config"] in [
               %{"background" => "blue"},
               %{"logo_url" => "logo.png"}
             ]

      assert Automerge.get_conflicts(s3, ["config"]) == %{
               "1@#{Automerge.get_actor_id(s1)}" => %{"background" => "blue"},
               "1@#{Automerge.get_actor_id(s2)}" => %{"logo_url" => "logo.png"}
             }
    end

    test "should clear conflicts after assigning a new value", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["field"], "one"))
      {s2, _change} = Automerge.change!(s2, &put_in(&1["field"], "two"))
      s3 = Automerge.merge!(s1, s2)

      {s3, _change} =
        Automerge.change!(s3, fn doc ->
          {_prev, doc} = get_and_update_in(doc, ["field"], fn field -> {field, "three"} end)

          doc
        end)

      assert Automerge.get_document(s3) == %{"field" => "three"}

      assert Automerge.get_conflicts(s3, ["field"]) == nil

      s2 = Automerge.merge!(s2, s3)

      assert Automerge.get_document(s2) == %{"field" => "three"}

      assert Automerge.get_conflicts(s3, ["field"]) == nil
    end

    test "should handle concurrent insertions at different list positions", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["list"], Automerge.list(["one", "three"])))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} =
            get_and_update_in(doc, ["list"], fn list ->
              {list, Automerge.List.insert_at(list, 1, "two")}
            end)

          doc
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          {_prev, doc} =
            get_and_update_in(doc, ["list"], fn list ->
              {list, Automerge.List.append(list, ["four"])}
            end)

          doc
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["list"] === ["one", "two", "three", "four"]
      assert Automerge.get_conflicts(s3, ["list"]) === nil
    end

    test "should handle concurrent insertions at the same list position", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["birds"], Automerge.list(["parakeet"])))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.append(birds, ["starling"])
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.append(birds, ["chaffinch"])
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["birds"] in [
               ["parakeet", "starling", "chaffinch"],
               ["parakeet", "chaffinch", "starling"]
             ]

      s2 = Automerge.merge!(s2, s3)

      assert Automerge.get_document(s2) == Automerge.get_document(s3)
    end

    test "should handle concurrent assignment and deletion of a map entry", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["bestBird"], "robin"))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["bestBird"])

          doc
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["bestBird"], fn _best_bird -> "magpie" end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s1) == %{}
      assert Automerge.get_document(s2) == %{"bestBird" => "magpie"}
      assert Automerge.get_document(s3) == %{"bestBird" => "magpie"}

      assert Automerge.get_conflicts(s2, ["bestBird"]) == nil
    end

    test "should handle concurrent assignment and deletion of a list element", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["birds"], Automerge.list(["blackbird", "thrush", "goldfinch"]))
        )

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.replace_at(birds, 1, "starling")
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.delete_at(birds, 1)
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s1)["birds"] == ["blackbird", "starling", "goldfinch"]
      assert Automerge.get_document(s2)["birds"] == ["blackbird", "goldfinch"]
      assert Automerge.get_document(s3)["birds"] == ["blackbird", "starling", "goldfinch"]
    end

    test "should handle insertion after a deleted list element", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["birds"], Automerge.list(["blackbird", "thrush", "goldfinch"]))
        )

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.splice(birds, 1, 2)
          end)
        end)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.splice(birds, 2, 0, ["starling"])
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

#      assert Automerge.get_document(s3) == %{"birds" => ["blackbird", "starling"]}

      assert Automerge.get_document(Automerge.merge!(s2, s3))["birds"] == [
               "blackbird",
               "starling"
             ]
    end

    test "should handle concurrent deletion of the same element", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["birds"], Automerge.list(["albatross", "buzzard", "cormorant"]))
        )

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.delete_at(birds, 1)
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.delete_at(birds, 1)
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["birds"] == ["albatross", "cormorant"]
    end

    test "should handle concurrent deletion of different elements", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["birds"], Automerge.list(["albatross", "buzzard", "cormorant"]))
        )

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.delete_at(birds, 0)
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["birds"], fn birds ->
            Automerge.List.delete_at(birds, 1)
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["birds"] == ["cormorant"]
    end

    test "should handle concurrent updates at different levels of the tree", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} =
        Automerge.change!(
          s1,
          &put_in(&1["animals"], %{
            "birds" => %{"pink" => "flamingo", "black" => "starling"},
            "mammals" => Automerge.list(["badger"])
          })
        )

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["animals"]["birds"], fn birds ->
            put_in(birds["brown"], "sparrow")
          end)
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          {_prev, doc} = pop_in(doc, ["animals", "birds"])

          doc
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s1)["animals"] == %{
               "birds" => %{"pink" => "flamingo", "black" => "starling", "brown" => "sparrow"},
               "mammals" => ["badger"]
             }

      assert Automerge.get_document(s2)["animals"] == %{
               "mammals" => ["badger"]
             }

      assert Automerge.get_document(s3)["animals"] == %{
               "mammals" => ["badger"]
             }
    end

    test "should handle updates of concurrently deleted objects", %{s1: s1, s2: s2, s3: _s3} do
      {s1, _change} =
        Automerge.change!(s1, &put_in(&1["birds"], %{"blackbird" => %{"feathers" => "black"}}))

      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} = pop_in(doc["birds"]["blackbird"])

          doc
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["birds", "blackbird"], fn blackbird ->
            put_in(blackbird["beak"], "orange")
          end)
        end)

      _s3 = Automerge.merge!(s1, s2)

      # HMM: Is this test unfinished in the JS lib?
      assert Automerge.get_document(s1)["birds"] == %{}
    end

    test "should not interleave sequence insertions at the same position", %{
      s1: s1,
      s2: s2,
      s3: _s3
    } do
      {s1, _change} = Automerge.change!(s1, &put_in(&1["wisdom"], Automerge.list()))
      s2 = Automerge.merge!(s2, s1)

      {s1, _change} =
        Automerge.change!(s1, fn doc ->
          {_prev, doc} =
            get_and_update_in(doc, ["wisdom"], fn wisdom ->
              {wisdom, Automerge.List.append(wisdom, ~w(to be is to do))}
            end)

          doc
        end)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["wisdom"], fn wisdom ->
            Automerge.List.append(wisdom, ~w(to do is to be))
          end)
        end)

      s3 = Automerge.merge!(s1, s2)

      assert Automerge.get_document(s3)["wisdom"] in [
               ~w(to be is to do) ++ ~w(to do is to be),
               ~w(to do is to be) ++ ~w(to be is to do)
             ]
    end
  end

  describe "multiple insertions at the same list position" do
    test "should handle insertion by greater actor ID" do
      s1 = Automerge.init("aaaa")
      s2 = Automerge.init("bbbb")

      {s1, _patch} =
        Automerge.change!(s1, fn doc -> put_in(doc, ["list"], Automerge.list(["two"])) end)

      s2 = Automerge.merge!(s2, s1)

      {s2, _patch} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "one")
          end)
        end)

      assert Automerge.get_document(s2)["list"] == ["one", "two"]
    end

    test "should handle insertion by lesser actor ID" do
      s1 = Automerge.init("bbbb")
      s2 = Automerge.init("aaaa")

      {s1, _patch} =
        Automerge.change!(s1, fn doc -> put_in(doc, ["list"], Automerge.list(["two"])) end)

      s2 = Automerge.merge!(s2, s1)

      {s2, _patch} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "one")
          end)
        end)

      assert Automerge.get_document(s2)["list"] == ["one", "two"]
    end

    test "should handle insertion regardless of actor ID" do
      s1 = Automerge.init()
      s2 = Automerge.init()

      {s1, _patch} =
        Automerge.change!(s1, fn doc -> put_in(doc, ["list"], Automerge.list(["two"])) end)

      s2 = Automerge.merge!(s2, s1)

      {s2, _patch} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "one")
          end)
        end)

      assert Automerge.get_document(s2)["list"] == ["one", "two"]
    end

    test "should make insertion order consistent with causality" do
      s1 = Automerge.init()
      s2 = Automerge.init()

      {s1, _patch} =
        Automerge.change!(s1, fn doc -> put_in(doc, ["list"], Automerge.list(["four"])) end)

      s2 = Automerge.merge!(s2, s1)

      {s2, _patch} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "three")
          end)
        end)

      s1 = Automerge.merge!(s1, s2)

      {s1, _patch} =
        Automerge.change!(s1, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "two")
          end)
        end)

      s2 = Automerge.merge!(s2, s1)

      {s2, _patch} =
        Automerge.change!(s2, fn doc ->
          update_in(doc, ["list"], fn list ->
            Automerge.List.prepend(list, "one")
          end)
        end)

      assert Automerge.get_document(s2)["list"] == ["one", "two", "three", "four"]
    end
  end

  describe "saving and loading" do
    test "should save and restore an empty document" do
      s = Automerge.init() |> Automerge.save() |> Automerge.load()

      assert Automerge.get_document(s) == %{}
    end

    test "should generate a new random actor ID" do
      s1 = Automerge.init()
      s2 = Automerge.load(Automerge.save(s1))

      assert Automerge.get_actor_id(s1) != Automerge.get_actor_id(s2)
    end

    test "'should allow a custom actor ID to be set" do
      s = Automerge.init() |> Automerge.save() |> Automerge.load("333333")

      assert Automerge.get_actor_id(s) == "333333"
    end

    test "should reconstitute complex datatypes" do
      {s1, _change} =
        Automerge.change!(
          Automerge.init(),
          &put_in(&1["todos"], Automerge.list([%{"title" => "water plants", "done" => false}]))
        )

      s2 = Automerge.load(Automerge.save(s1))

      assert Automerge.get_document(s2)["todos"] == [
               %{"title" => "water plants", "done" => false}
             ]
    end

    test "should save and load maps with @ symbols in the keys" do
      {s1, _change} = Automerge.change!(Automerge.init(), &put_in(&1["123@4567"], "hello"))
      s2 = Automerge.load(Automerge.save(s1))

      assert Automerge.get_document(s2)["123@4567"] == "hello"
    end

    test "should reconstitute conflicts" do
      {s1, _change} = Automerge.change!(Automerge.init("111111"), &put_in(&1["x"], 3))
      {s2, _change} = Automerge.change!(Automerge.init("222222"), &put_in(&1["x"], 5))
      s1 = Automerge.merge!(s1, s2)

      s3 = Automerge.load(Automerge.save(s1))

      assert Automerge.get_document(s1)["x"] == 5
      assert Automerge.get_document(s3)["x"] == 5

      assert Automerge.get_conflicts(s1, ["x"]) === %{"1@111111" => 3, "1@222222" => 5}
      assert Automerge.get_conflicts(s3, ["x"]) === %{"1@111111" => 3, "1@222222" => 5}
    end

    test "should reconstitute element ID counters" do
      s1 = Automerge.init("01234567")
      {s2, _change} = Automerge.change!(s1, &put_in(&1["list"], Automerge.list(["a"])))
      list_id = Automerge.get_object_id(s2["list"])

      changes12 = s2 |> Automerge.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert changes12 == [
               %{
                 "hash" => Enum.at(changes12, 0)["hash"],
                 "actor" => "01234567",
                 "seq" => 1,
                 "startOp" => 1,
                 "time" => Enum.at(changes12, 0)["time"],
                 "message" => nil,
                 "deps" => [],
                 "ops" => [
                   %{
                     "obj" => "_root",
                     "action" => "makeList",
                     "key" => "list",
                     "pred" => []
                   },
                   %{
                     "obj" => list_id,
                     "action" => "set",
                     "elemId" => "_head",
                     "insert" => true,
                     "value" => "a",
                     "pred" => []
                   }
                 ]
               }
             ]

      {s3, _changes} =
        Automerge.change!(s2, fn doc ->
          update_in(doc["list"], fn list ->
            Automerge.List.delete_at(list, 0)
          end)
        end)

      s4 = s3 |> Automerge.save() |> Automerge.load("01234567")

      {s5, _patch} =
        Automerge.change!(s4, fn doc ->
          update_in(doc["list"], fn list ->
            Automerge.List.append(list, ["b"])
          end)
        end)

      changes45 = s5 |> Automerge.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert Automerge.get_document(s5)["list"] == ["b"]

      assert Enum.at(changes45, 2) ==
               %{
                 "hash" => Enum.at(changes45, 2)["hash"],
                 "actor" => "01234567",
                 "seq" => 3,
                 "startOp" => 4,
                 "time" => Enum.at(changes45, 2)["time"],
                 "message" => nil,
                 "deps" => [Enum.at(changes45, 1)["hash"]],
                 "ops" => [
                   %{
                     "obj" => list_id,
                     "action" => "set",
                     "elemId" => "_head",
                     "insert" => true,
                     "value" => "b",
                     "pred" => []
                   }
                 ]
               }
    end

    test "should allow a reloaded list to be mutated" do
      {s1, _change} = Automerge.change!(Automerge.init("111111"), &put_in(&1["x"], 3))
      {s2, _change} = Automerge.change!(Automerge.init("222222"), &put_in(&1["x"], 5))
      s1 = Automerge.merge!(s1, s2)

      s3 = Automerge.load(Automerge.save(s1))

      assert Automerge.get_document(s1)["x"] == 5
      assert Automerge.get_document(s3)["x"] == 5

      assert Automerge.get_conflicts(s1, ["x"]) === %{"1@111111" => 3, "1@222222" => 5}
      assert Automerge.get_conflicts(s3, ["x"]) === %{"1@111111" => 3, "1@222222" => 5}
    end

    @tag :patch_callback
    test "should call patchCallback if supplied" do
    end
  end

  describe "history api" do
    test "should return an empty history for an empty document" do
      assert Automerge.get_history(Automerge.init()) == []
    end

    test "should make past document states accessible" do
      s = Automerge.init()

      {s, _change} = Automerge.change!(s, &put_in(&1["config"], %{"background" => "blue"}))
      {s, _change} = Automerge.change!(s, &put_in(&1["birds"], Automerge.list(["mallard"])))

      {s, _change} =
        Automerge.change!(
          s,
          &update_in(&1["birds"], fn birds -> Automerge.List.prepend(birds, "oystercatcher") end)
        )

      assert s
             |> Automerge.get_history()
             |> Enum.map(fn state ->
               state
               |> Automerge.History.get_snapshot!()
               |> Automerge.get_document()
             end) == [
               %{"config" => %{"background" => "blue"}},
               %{"config" => %{"background" => "blue"}, "birds" => ["mallard"]},
               %{"config" => %{"background" => "blue"}, "birds" => ["oystercatcher", "mallard"]}
             ]
    end

    test "should make change messages accessible" do
      s = Automerge.init()

      {s, _change} =
        Automerge.change!(s, "Empty Bookshelf", &put_in(&1["books"], Automerge.list()))

      {s, _change} =
        Automerge.change!(s, "Add Orwell", fn doc ->
          update_in(doc["books"], fn books ->
            Automerge.List.append(books, ["Nineteen Eighty-Four"])
          end)
        end)

      {s, _change} =
        Automerge.change!(s, "Add Huxley", fn doc ->
          update_in(doc["books"], fn books ->
            Automerge.List.append(books, ["Brave New World"])
          end)
        end)

      assert Automerge.get_document(s)["books"] == ["Nineteen Eighty-Four", "Brave New World"]

      assert s
             |> Automerge.get_history()
             |> Enum.map(fn state ->
               state
               |> Automerge.History.get_change!()
               |> get_in(["message"])
             end) == [
               "Empty Bookshelf",
               "Add Orwell",
               "Add Huxley"
             ]
    end
  end

  describe "changes api" do
    test "should return an empty list on an empty document" do
      changes = Automerge.get_all_changes(Automerge.init())
      assert changes === []
    end

    test "should return an empty list when nothing changed" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      assert Automerge.get_changes(s1, s1) === []
    end

    test "should do nothing when applying an empty list of changes" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      assert s1 |> Automerge.apply_changes([]) |> Automerge.get_document() ==
               Automerge.get_document(s1)
    end

    test "should return all changes when compared to an empty document" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), "Add Chaffinch", fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      {s2, _change} =
        Automerge.change!(s1, "Add Bullfinch", fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.append(birds, ["Bullfinch"])
          end)
        end)

      changes = Automerge.get_changes(Automerge.init(), s2)
      assert Enum.count(changes) == 2
    end

    test "should allow a document copy to be reconstructed from scratch" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), "Add Chaffinch", fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      {s2, _change} =
        Automerge.change!(s1, "Add Chaffinch", fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.append(birds, ["Bullfinch"])
          end)
        end)

      changes = Automerge.get_all_changes(s2)
      s3 = Automerge.apply_changes(Automerge.init(), changes)

      assert Automerge.get_document(s3)["birds"] == ["Chaffinch", "Bullfinch"]
    end

    test "should return changes since the last given version" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), "Add Chaffinch", fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      changes1 = Automerge.get_all_changes(s1)

      {s2, _change} =
        Automerge.change!(s1, "Add Chaffinch", fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.append(birds, ["Bullfinch"])
          end)
        end)

      changes2 = Automerge.get_changes(s1, s2)

      assert Enum.count(changes1) == 1
      assert Enum.count(changes2) == 1
    end

    test "should incrementally apply changes since the last given version" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), "Add Chaffinch", fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      changes1 = Automerge.get_all_changes(s1)

      {s2, _change} =
        Automerge.change!(s1, "Add Bullfinch", fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.append(birds, ["Bullfinch"])
          end)
        end)

      changes2 = Automerge.get_changes(s1, s2)

      s3 = Automerge.apply_changes(Automerge.init(), changes1)
      s4 = Automerge.apply_changes(s3, changes2)

      assert Automerge.get_document(s3)["birds"] == ["Chaffinch"]
      assert Automerge.get_document(s4)["birds"] == ["Chaffinch", "Bullfinch"]
    end

    test "should report missing dependencies" do
      {s1, _change} =
        Automerge.change!(Automerge.init(), fn doc ->
          put_in(doc["birds"], Automerge.list(["Chaffinch"]))
        end)

      s2 = Automerge.merge!(Automerge.init(), s1)

      {s2, _change} =
        Automerge.change!(s2, fn doc ->
          update_in(doc["birds"], fn birds ->
            Automerge.List.append(birds, ["Bullfinch"])
          end)
        end)

      changes = Automerge.get_all_changes(s2)

      s3 = Automerge.apply_changes(Automerge.init(), [Enum.at(changes, 1)])

      assert Automerge.get_document(s3) == %{}
      assert Automerge.get_missing_deps(s3) == Backend.decode_change(Enum.at(changes, 1))["deps"]

      s3 = Automerge.apply_changes(s3, [Enum.at(changes, 0)])

      assert Automerge.get_document(s3)["birds"] == ["Chaffinch", "Bullfinch"]
      assert Automerge.get_missing_deps(s3) == []
    end

    test "should report missing dependencies with out-of-order applyChanges" do
      s0 = Automerge.init()

      {s1, _change} =
        Automerge.change!(s0, fn doc -> put_in(doc["test"], Automerge.list(["a"])) end)

      changes01 = Automerge.get_all_changes(s1)

      {s2, _change} =
        Automerge.change!(s1, fn doc -> put_in(doc["test"], Automerge.list(["b"])) end)

      changes12 = Automerge.get_changes(s1, s2)

      {s3, _change} =
        Automerge.change!(s2, fn doc -> put_in(doc["test"], Automerge.list(["c"])) end)

      changes23 = Automerge.get_changes(s2, s3)

      s4 = Automerge.init()

      s5 = Automerge.apply_changes(s4, changes23)
      s6 = Automerge.apply_changes(s5, changes12)

      assert Automerge.get_missing_deps(s6) == [
               Map.get(
                 Backend.decode_change(Enum.at(changes01, 0)),
                 "hash"
               )
             ]
    end

    @tag :patch_callback
    test "should call patchCallback if supplied when applying changes" do
    end

    @tag :patch_callback
    test "should merge multiple applied changes into one patch" do
    end

    @tag :patch_callback
    test "should call a patchCallback registered on doc initialisation" do
    end
  end
end
