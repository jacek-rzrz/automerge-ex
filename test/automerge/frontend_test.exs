defmodule Automerge.FrontendTest do
  use Automerge.HelperCase, async: true

  @root_id "_root"

  alias Automerge.Frontend
  alias Automerge.Backend.NIF, as: Backend

  describe "init/1" do
    test "default" do
      %Automerge{
        _cache: cache,
        _conflicts: conflicts,
        _object_id: object_id,
        _options: options,
        _state: state
      } = Frontend.init([])

      assert %{@root_id => %Automerge.Map{_object_id: @root_id}} == cache
      assert %{} == conflicts
      assert @root_id == object_id
      assert options[:backend] == nil
      assert match?({:ok, _info}, UUID.info(options[:actor_id]))

      assert %Automerge.State{
               seq: 0,
               actor_id: nil,
               requests: [],
               deps: [],
               backend_state: nil
             } == state
    end

    test "deferred actor id" do
      %Automerge{_options: options} = Automerge.init(defer_actor_id: true)

      assert options[:actor_id] == nil
      assert options[:defer_actor_id] == true
    end

    test "set actor id" do
      actor_id = uuid()

      %Automerge{_options: options} = Automerge.init(actor_id: actor_id)

      assert options[:actor_id] == actor_id
    end
  end

  describe "get_actor_id/1" do
    test "matches when actor_id is set" do
      actor_id = uuid()

      document = Automerge.init(actor_id: actor_id)

      assert actor_id == Automerge.get_actor_id(document)
    end

    test "uuid is assigned by default" do
      document = Automerge.init()
      actor_id = Automerge.get_actor_id(document)

      {:ok, uuid_info} = UUID.info(actor_id)

      assert uuid_info.version == 4
    end

    test "actor_id is nil if deferred_actor_id is set" do
      document = Automerge.init(defer_actor_id: true)

      actor_id = Automerge.get_actor_id(document)

      assert actor_id === nil
    end
  end

  describe "set_actor_id/2" do
    test "can set actor id" do
      document = Automerge.init(defer_actor_id: true)

      actor_id = Automerge.get_actor_id(document)

      assert actor_id == nil

      actor_id = uuid()

      document = Automerge.set_actor_id(document, actor_id)

      assert Automerge.get_actor_id(document) === actor_id
    end

    test "actor id changes when set" do
      document = Automerge.init()

      default_actor_id = Automerge.get_actor_id(document)

      actor_id = uuid()

      document = Automerge.set_actor_id(document, actor_id)

      assert default_actor_id !== Automerge.get_actor_id(document)
      assert actor_id === Automerge.get_actor_id(document)
    end
  end

  describe "change!/2" do
    test "should return the unmodified document if nothing changed" do
      doc0 = Frontend.init([])
      {doc1, _req} = Frontend.change!(doc0, & &1)

      assert doc0 == doc1
    end

    test "should set root object properties" do
      actor_id = uuid()

      {_doc, change} =
        [actor_id: actor_id]
        |> Frontend.init()
        |> Frontend.change!(fn doc -> put_in(doc["bird"], "magpie") end)

      assert change == %{
               "actor" => actor_id,
               "seq" => 1,
               "time" => Map.get(change, "time"),
               "message" => nil,
               "startOp" => 1,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "bird",
                   "insert" => false,
                   "value" => "magpie",
                   "pred" => []
                 }
               ]
             }
    end

    test "should create nested maps" do
      actor_id = uuid()

      {doc, change} =
        [actor_id: actor_id]
        |> Frontend.init()
        |> Frontend.change!(fn doc -> put_in(doc["birds"], %{"wrens" => 3}) end)

      birds = Automerge.get_object_id(doc["birds"]["wrens"])
      assert Automerge.get_document(doc) == %{"birds" => %{"wrens" => 3}}

      assert change == %{
               "actor" => actor_id,
               "seq" => 1,
               "time" => Map.get(change, "time"),
               "message" => nil,
               "startOp" => 1,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "makeMap",
                   "key" => "birds",
                   "insert" => false,
                   "pred" => []
                 },
                 %{
                   "obj" => birds,
                   "action" => "set",
                   "key" => "wrens",
                   "insert" => false,
                   "value" => 3,
                   "pred" => []
                 }
               ]
             }
    end

    test "should apply updates inside nested maps" do
      actor_id = uuid()
      doc0 = Frontend.init(actor_id: actor_id)

      {doc1, _change1} =
        Frontend.change!(doc0, fn doc -> put_in(doc["birds"], %{"wrens" => 3}) end)

      {doc2, change2} =
        Frontend.change!(doc1, fn doc ->
          update_in(doc["birds"], &put_in(&1["sparrows"], 15))
        end)

      birds = Automerge.get_object_id(doc2["birds"]["wrens"])

      assert Automerge.get_document(doc1) == %{"birds" => %{"wrens" => 3}}
      assert Automerge.get_document(doc2) == %{"birds" => %{"wrens" => 3, "sparrows" => 15}}

      assert change2 == %{
               "actor" => actor_id,
               "seq" => 2,
               "time" => Map.get(change2, "time"),
               "message" => nil,
               "startOp" => 3,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => birds,
                   "action" => "set",
                   "key" => "sparrows",
                   "insert" => false,
                   "value" => 15,
                   "pred" => []
                 }
               ]
             }
    end

    test "should delete keys in maps" do
      actor_id = uuid()
      doc0 = Frontend.init(actor_id: actor_id)

      {doc1, _change1} =
        Frontend.change!(doc0, fn doc -> Map.merge(doc, %{"magpies" => 2, "sparrows" => 15}) end)

      {doc2, change2} =
        Frontend.change!(doc1, fn doc ->
          {_prev, doc} = pop_in(doc, ["magpies"])
          doc
        end)

      assert Automerge.get_document(doc1) == %{"magpies" => 2, "sparrows" => 15}
      assert Automerge.get_document(doc2) == %{"sparrows" => 15}

      assert change2 == %{
               "actor" => actor_id,
               "seq" => 2,
               "time" => Map.get(change2, "time"),
               "message" => nil,
               "startOp" => 3,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "del",
                   "key" => "magpies",
                   "insert" => false,
                   "pred" => ["1@#{actor_id}"]
                 }
               ]
             }
    end

    test "should create lists" do
      actor_id = uuid()
      doc0 = Frontend.init(actor_id: actor_id)

      {doc1, change1} =
        Frontend.change!(doc0, fn doc -> put_in(doc["birds"], Automerge.list(["chaffinch"])) end)

      _birds = Automerge.get_object_id(doc1["birds"])

      assert Automerge.get_document(doc1) == %{"birds" => ["chaffinch"]}

      assert change1 == %{
               "actor" => actor_id,
               "seq" => 1,
               "time" => Map.get(change1, "time"),
               "message" => nil,
               "startOp" => 1,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "makeList",
                   "key" => "birds",
                   "insert" => false,
                   "pred" => []
                 },
                 %{
                   "obj" => "1@#{actor_id}",
                   "action" => "set",
                   "elemId" => "_head",
                   "insert" => true,
                   "value" => "chaffinch",
                   "pred" => []
                 }
               ]
             }
    end

    test "should delete list elements" do
      actor_id = uuid()
      doc0 = Frontend.init(actor_id: actor_id)

      {doc1, change1} =
        Frontend.change!(doc0, fn doc ->
          put_in(doc["birds"], Automerge.list(["chaffinch", "goldfinch"]))
        end)

      {doc2, change2} =
        Frontend.change!(doc1, fn doc ->
          update_in(doc["birds"], fn birds -> Automerge.List.delete_at(birds, 0) end)
        end)

      birds = Automerge.get_object_id(doc1["birds"])

      assert Automerge.get_document(doc1) == %{"birds" => ["chaffinch", "goldfinch"]}
      assert Automerge.get_document(doc2) == %{"birds" => ["goldfinch"]}

      assert change2 == %{
               "actor" => actor_id,
               "seq" => 2,
               "time" => Map.get(change1, "time"),
               "message" => nil,
               "startOp" => 4,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => birds,
                   "action" => "del",
                   "elemId" => "2@#{actor_id}",
                   "insert" => false,
                   "pred" => ["2@#{actor_id}"]
                 }
               ]
             }
    end
  end

  describe "backend concurrency" do
    def get_requests(doc) do
      Enum.map(doc._state.requests, fn req ->
        %{"actor" => req["actor"], "seq" => req["seq"]}
      end)
    end

    test "should use version and sequence number from the backend" do
      local = uuid()
      remote1 = uuid()
      remote2 = uuid()

      patch1 = %{
        "clock" => %{"#{local}" => 4, "#{remote1}" => 11, "#{remote2}" => 41},
        "maxOp" => 4,
        "deps" => [],
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "blackbirds" => %{"#{local}" => %{"value" => 24}}
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(local), patch1)

      {doc2, change} =
        Frontend.change!(doc1, fn doc ->
          put_in(doc, ["partridges"], 1)
        end)

      assert change == %{
               "actor" => local,
               "seq" => 5,
               "deps" => [],
               "startOp" => 5,
               "time" => Map.get(change, "time"),
               "message" => nil,
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "partridges",
                   "insert" => false,
                   "value" => 1,
                   "pred" => []
                 }
               ]
             }

      assert get_requests(doc2) == [%{"actor" => local, "seq" => 5}]
    end

    test "should remove pending requests once handled" do
      actor = uuid()

      {doc1, change1} =
        Frontend.change!(Frontend.init(actor), fn doc ->
          put_in(doc["blackbirds"], 24)
        end)

      {doc2, change2} =
        Frontend.change!(doc1, fn doc ->
          put_in(doc["partridges"], 1)
        end)

      assert change1 == %{
               "actor" => actor,
               "seq" => 1,
               "deps" => [],
               "startOp" => 1,
               "time" => Map.get(change1, "time"),
               "message" => nil,
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "blackbirds",
                   "insert" => false,
                   "value" => 24,
                   "pred" => []
                 }
               ]
             }

      assert change2 == %{
               "actor" => actor,
               "seq" => 2,
               "deps" => [],
               "startOp" => 2,
               "time" => Map.get(change2, "time"),
               "message" => nil,
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "partridges",
                   "insert" => false,
                   "value" => 1,
                   "pred" => []
                 }
               ]
             }

      assert get_requests(doc2) == [
               %{"actor" => actor, "seq" => 1},
               %{"actor" => actor, "seq" => 2}
             ]

      doc2 =
        Frontend.apply_patch!(doc2, %{
          "actor" => actor,
          "seq" => 1,
          "clock" => %{"#{actor}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "blackbirds" => %{
                "#{actor}" => %{"value" => 24}
              }
            }
          }
        })

      assert get_requests(doc2) == [%{"actor" => actor, "seq" => 2}]

      assert Automerge.get_document(doc2) == %{"blackbirds" => 24, "partridges" => 1}

      doc2 =
        Frontend.apply_patch!(doc2, %{
          "actor" => actor,
          "seq" => 2,
          "clock" => %{"#{actor}" => 2},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "partridges" => %{
                "#{actor}" => %{"value" => 1}
              }
            }
          }
        })

      assert Automerge.get_document(doc2) == %{"blackbirds" => 24, "partridges" => 1}

      assert get_requests(doc2) === []
    end

    test "should leave the request queue unchanged on remote patches" do
      actor = uuid()
      other = uuid()

      {doc, req} =
        Frontend.change!(Frontend.init(actor), fn doc ->
          put_in(doc["blackbirds"], 24)
        end)

      assert req == %{
               "actor" => actor,
               "seq" => 1,
               "time" => Map.get(req, "time"),
               "message" => nil,
               "startOp" => 1,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "blackbirds",
                   "insert" => false,
                   "value" => 24,
                   "pred" => []
                 }
               ]
             }

      assert get_requests(doc) == [%{"actor" => actor, "seq" => 1}]

      doc =
        Frontend.apply_patch!(doc, %{
          "clock" => %{"#{other}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "pheasants" => %{
                "#{other}" => %{"value" => 2}
              }
            }
          }
        })

      assert Automerge.get_document(doc) == %{"blackbirds" => 24}

      assert get_requests(doc) == [%{"actor" => actor, "seq" => 1}]

      doc =
        Frontend.apply_patch!(doc, %{
          "actor" => actor,
          "seq" => 1,
          "clock" => %{"#{actor}" => 1, "#{other}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "blackbirds" => %{
                "#{actor}" => %{"value" => 24}
              }
            }
          }
        })

      assert Automerge.get_document(doc) == %{"blackbirds" => 24}
      assert get_requests(doc) == [%{"actor" => actor, "seq" => 1}]
    end

    test "should not allow request patches to be applied out of order" do
      {doc1, _req1} =
        Frontend.change!(Frontend.init(), fn doc -> put_in(doc, ["blackbirds"], 24) end)

      {doc2, _req2} = Frontend.change!(doc1, fn doc -> put_in(doc, ["partridges"], 1) end)
      actor = Automerge.get_actor_id(doc2)

      diffs = %{
        "objectId" => "_root",
        "type" => "map",
        "props" => %{"partridges" => %{"#{actor}" => %{"value" => 1}}}
      }

      assert_raise RuntimeError, ~r/Mismatched sequence number/, fn ->
        Frontend.apply_patch!(doc2, %{
          "actor" => actor,
          "seq" => 2,
          "clock" => %{"#{actor}" => 2},
          "diffs" => diffs
        })
      end
    end

    test "should handle concurrent insertions into lists" do
      {doc1, _req1} =
        Frontend.change!(Frontend.init(), fn doc ->
          put_in(doc["birds"], Automerge.list(["goldfinch"]))
        end)

      birds = Automerge.get_object_id(doc1["birds"])
      actor = Automerge.get_actor_id(doc1)

      doc1 =
        Frontend.apply_patch!(doc1, %{
          "actor" => actor,
          "seq" => 1,
          "clock" => %{"#{actor}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "birds" => %{
                "#{actor}" => %{
                  "objectId" => birds,
                  "type" => "list",
                  "edits" => [%{"action" => "insert", "index" => 0}],
                  "props" => %{0 => %{"#{actor}" => %{"value" => "goldfinch"}}}
                }
              }
            }
          }
        })

      assert Automerge.get_document(doc1) == %{"birds" => ["goldfinch"]}
      assert get_requests(doc1) == []

      {doc2, _req2} =
        Frontend.change!(doc1, fn doc ->
          update_in(doc["birds"], fn birds ->
            birds
            |> Automerge.List.insert_at(0, "chaffinch")
            |> Automerge.List.insert_at(2, "greenfinch")
          end)
        end)

      assert Automerge.get_document(doc2) == %{
               "birds" => ["chaffinch", "goldfinch", "greenfinch"]
             }

      remote_actor = uuid()

      doc3 =
        Frontend.apply_patch!(doc2, %{
          "clock" => %{"#{actor}" => 1, "#{remote_actor}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "birds" => %{
                "#{actor}" => %{
                  "objectId" => birds,
                  "type" => "list",
                  "edits" => [%{"action" => "insert", "index" => 1}],
                  "props" => %{1 => %{"#{remote_actor}" => %{"value" => "bullfinch"}}}
                }
              }
            }
          }
        })

      assert Automerge.get_document(doc3) == %{
               "birds" => ["chaffinch", "goldfinch", "greenfinch"]
             }

      doc4 =
        Frontend.apply_patch!(doc3, %{
          "actor" => actor,
          "seq" => 2,
          "clock" => %{"#{actor}" => 2, "#{remote_actor}" => 1},
          "diffs" => %{
            "objectId" => "_root",
            "type" => "map",
            "props" => %{
              "birds" => %{
                "#{actor}" => %{
                  "objectId" => birds,
                  "type" => "list",
                  "edits" => [
                    %{"action" => "insert", "index" => 0},
                    %{"action" => "insert", "index" => 2}
                  ],
                  "props" => %{
                    0 => %{"#{actor}" => %{"value" => "chaffinch"}},
                    2 => %{"#{actor}" => %{"value" => "greenfinch"}}
                  }
                }
              }
            }
          }
        })

      assert Automerge.get_document(doc4) == %{
               "birds" => ["chaffinch", "goldfinch", "greenfinch", "bullfinch"]
             }

      assert get_requests(doc4) == []
    end

    test "should allow interleaving of patches and changes" do
      actor = uuid()

      {doc1, change1} =
        Frontend.change!(Frontend.init(actor), fn doc -> put_in(doc["number"], 1) end)

      {doc2, change2} =
        Frontend.change!(doc1, fn doc ->
          update_in(doc["number"], fn _num -> 2 end)
        end)

      assert change1 == %{
               "actor" => actor,
               "seq" => 1,
               "time" => Map.get(change1, "time"),
               "message" => nil,
               "startOp" => 1,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 1,
                   "pred" => []
                 }
               ]
             }

      assert change2 == %{
               "actor" => actor,
               "seq" => 2,
               "time" => Map.get(change2, "time"),
               "message" => nil,
               "startOp" => 2,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 2,
                   "pred" => ["1@#{actor}"]
                 }
               ]
             }

      state0 = Backend.init()

      {_state1, patch1, _binChange1} = Backend.apply_local_change(state0, change1)
      doc2a = Frontend.apply_patch!(doc2, patch1)

      {_doc3, change3} =
        Frontend.change!(doc2a, fn doc ->
          update_in(doc["number"], fn _num -> 3 end)
        end)

      assert change3 == %{
               "actor" => actor,
               "seq" => 3,
               "time" => Map.get(change3, "time"),
               "message" => nil,
               "startOp" => 3,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 3,
                   "pred" => ["2@#{actor}"]
                 }
               ]
             }
    end

    test "deps are filled in if the frontend does not have the latest patch" do
      actor1 = uuid()
      actor2 = uuid()

      {_doc1, change1} =
        Frontend.change!(Frontend.init(actor1), fn doc -> put_in(doc, ["number"], 1) end)

      {_state1, _patch1, binChange1} = Backend.apply_local_change(Backend.init(), change1)
      {state1a, patch1a} = Backend.apply_changes(Backend.init(), [binChange1])

      doc1a = Frontend.apply_patch!(Frontend.init(actor2), patch1a)
      {doc2, change2} = Frontend.change!(doc1a, fn doc -> put_in(doc, ["number"], 2) end)
      {doc3, change3} = Frontend.change!(doc2, fn doc -> put_in(doc, ["number"], 3) end)

      assert change2 == %{
               "actor" => actor2,
               "seq" => 1,
               "time" => Map.get(change2, "time"),
               "message" => nil,
               "startOp" => 2,
               "deps" => [Backend.decode_change(binChange1)["hash"]],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 2,
                   "pred" => ["1@#{actor1}"]
                 }
               ]
             }

      assert change3 == %{
               "actor" => actor2,
               "seq" => 2,
               "time" => Map.get(change3, "time"),
               "message" => nil,
               "startOp" => 3,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 3,
                   "pred" => ["2@#{actor2}"]
                 }
               ]
             }

      {state2, patch2, binChange2} = Backend.apply_local_change(state1a, change2)
      {state3, patch3, binChange3} = Backend.apply_local_change(state2, change3)

      assert Backend.decode_change(binChange2)["deps"] == [
               Backend.decode_change(binChange1)["hash"]
             ]

      assert Backend.decode_change(binChange3)["deps"] == [
               Backend.decode_change(binChange2)["hash"]
             ]

      assert patch1a["deps"] == [Backend.decode_change(binChange1)["hash"]]
      assert patch2["deps"] == []

      doc2a = Frontend.apply_patch!(doc3, patch2)
      doc3a = Frontend.apply_patch!(doc2a, patch3)

      {_doc4, change4} = Frontend.change!(doc3a, fn doc -> put_in(doc, ["number"], 4) end)

      assert change4 == %{
               "actor" => actor2,
               "seq" => 3,
               "time" => Map.get(change4, "time"),
               "message" => nil,
               "startOp" => 4,
               "deps" => [],
               "ops" => [
                 %{
                   "obj" => "_root",
                   "action" => "set",
                   "key" => "number",
                   "insert" => false,
                   "value" => 4,
                   "pred" => ["3@#{actor2}"]
                 }
               ]
             }

      {_state4, _patch4, binChange4} = Backend.apply_local_change(state3, change4)

      assert Backend.decode_change(binChange4)["deps"] == [
               Backend.decode_change(binChange3)["hash"]
             ]
    end
  end

  describe "applying patches" do
    test "should set root object properties" do
      actor = uuid()

      patch = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{"bird" => %{"#{actor}" => %{"value" => "magpie"}}}
        }
      }

      doc = Frontend.apply_patch!(Frontend.init(), patch)
      assert Automerge.get_document(doc) == %{"bird" => "magpie"}
    end

    test "should reveal conflicts on root object properties" do
      patch = %{
        "clock" => %{"actor1" => 1, "actor2" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "favoriteBird" => %{
              "actor1" => %{"value" => "robin"},
              "actor2" => %{"value" => "wagtail"}
            }
          }
        }
      }

      doc = Frontend.apply_patch!(Frontend.init(), patch)
      assert Automerge.get_document(doc) == %{"favoriteBird" => "wagtail"}

      assert Automerge.get_conflicts(doc, ["favoriteBird"]) == %{
               "actor1" => "robin",
               "actor2" => "wagtail"
             }
    end

    test "should create nested maps" do
      birds = uuid()
      actor = uuid()

      patch = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "bird" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "map",
                "props" => %{"wrens" => %{"#{actor}" => %{"value" => 3}}}
              }
            }
          }
        }
      }

      doc = Frontend.apply_patch!(Frontend.init(), patch)
      assert Automerge.get_document(doc) == %{"bird" => %{"wrens" => 3}}
    end

    test "should apply updates inside nested maps" do
      birds = uuid()
      actor = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "map",
                "props" => %{"wrens" => %{"#{actor}" => %{"value" => 3}}}
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "map",
                "props" => %{"sparrows" => %{"#{actor}" => %{"value" => 15}}}
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{"birds" => %{"wrens" => 3}}
      assert Automerge.get_document(doc2) == %{"birds" => %{"wrens" => 3, "sparrows" => 15}}
    end

    test "should apply updates inside map key conflicts" do
      birds1 = uuid()
      birds2 = uuid()

      patch1 = %{
        "clock" => %{"#{birds1}" => 1, "#{birds2}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "favoriteBirds" => %{
              "actor1" => %{
                "objectId" => birds1,
                "type" => "map",
                "props" => %{"blackbirds" => %{"actor1" => %{"value" => 1}}}
              },
              "actor2" => %{
                "objectId" => birds2,
                "type" => "map",
                "props" => %{"wrens" => %{"actor2" => %{"value" => 3}}}
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{birds1}" => 2, "#{birds2}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "favoriteBirds" => %{
              "actor1" => %{
                "objectId" => birds1,
                "type" => "map",
                "props" => %{"blackbirds" => %{"actor1" => %{"value" => 2}}}
              },
              "actor2" => %{
                "objectId" => birds2,
                "type" => "map"
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{"favoriteBirds" => %{"wrens" => 3}}
      assert Automerge.get_document(doc2) == %{"favoriteBirds" => %{"wrens" => 3}}

      assert Automerge.get_conflicts(doc1, ["favoriteBirds"]) == %{
               "actor1" => %{"blackbirds" => 1},
               "actor2" => %{"wrens" => 3}
             }
    end

    test "should structure-share unmodified objects" do
      birds = uuid()
      mammals = uuid()
      actor = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "map",
                "props" => %{"wrens" => %{"#{actor}" => %{"value" => 3}}}
              }
            },
            "mammals" => %{
              "#{actor}" => %{
                "objectId" => mammals,
                "type" => "map",
                "props" => %{"badgers" => %{"#{actor}" => %{"value" => 1}}}
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "map",
                "props" => %{"sparrows" => %{"#{actor}" => %{"value" => 15}}}
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{
               "birds" => %{"wrens" => 3},
               "mammals" => %{"badgers" => 1}
             }

      assert Automerge.get_document(doc2) == %{
               "birds" => %{"wrens" => 3, "sparrows" => 15},
               "mammals" => %{"badgers" => 1}
             }

      assert Map.get(Automerge.get_document(doc1), "mammals") ==
               Map.get(Automerge.get_document(doc2), "mammals")
    end

    test "should delete keys in maps" do
      actor = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "magpies" => %{
              "#{actor}" => %{
                "value" => 2
              }
            },
            "sparrows" => %{
              "#{actor}" => %{
                "value" => 15
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "magpies" => %{}
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{"magpies" => 2, "sparrows" => 15}
      assert Automerge.get_document(doc2) == %{"sparrows" => 15}
    end

    test "should create lists" do
      actor = uuid()
      birds = uuid()

      patch = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [%{"action" => "insert", "index" => 0}],
                "props" => %{0 => %{"#{actor}" => %{"value" => "chaffinch"}}}
              }
            }
          }
        }
      }

      doc = Frontend.apply_patch!(Frontend.init(), patch)
      assert Automerge.get_document(doc) == %{"birds" => ["chaffinch"]}
    end

    test "should apply updates inside lists" do
      actor = uuid()
      birds = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [%{"action" => "insert", "index" => 0}],
                "props" => %{0 => %{"#{actor}" => %{"value" => "chaffinch"}}}
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [],
                "props" => %{0 => %{"#{actor}" => %{"value" => "greenfinch"}}}
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{"birds" => ["chaffinch"]}
      assert Automerge.get_document(doc2) == %{"birds" => ["greenfinch"]}
    end

    test "should apply updates inside list element conflicts" do
      actor = uuid()
      birds = uuid()
      items1 = uuid()
      items2 = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [%{"action" => "insert", "index" => 0}],
                "props" => %{
                  0 => %{
                    "actor1" => %{
                      "objectId" => items1,
                      "type" => "map",
                      "props" => %{
                        "species" => %{"actor1" => %{"value" => "woodpecker"}},
                        "numSeen" => %{"actor1" => %{"value" => 1}}
                      }
                    },
                    "actor2" => %{
                      "objectId" => items2,
                      "type" => "map",
                      "props" => %{
                        "species" => %{"actor1" => %{"value" => "lapwing"}},
                        "numSeen" => %{"actor1" => %{"value" => 2}}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [],
                "props" => %{
                  0 => %{
                    "actor1" => %{
                      "objectId" => items1,
                      "type" => "map",
                      "props" => %{
                        "numSeen" => %{"actor1" => %{"value" => 2}}
                      }
                    },
                    "actor2" => %{
                      "objectId" => items2,
                      "type" => "map"
                    }
                  }
                }
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{
               "birds" => [%{"species" => "lapwing", "numSeen" => 2}]
             }

      assert Automerge.get_document(doc2) == %{
               "birds" => [%{"species" => "lapwing", "numSeen" => 2}]
             }

      assert Enum.at(Automerge.get_document(doc1), 0) ==
               Enum.at(Automerge.get_document(doc2), 0)

      assert Automerge.get_conflicts(doc1, ["birds", 0]) == %{
               "actor1" => %{"species" => "woodpecker", "numSeen" => 1},
               "actor2" => %{"species" => "lapwing", "numSeen" => 2}
             }

      assert Automerge.get_conflicts(doc2, ["birds", 0]) == %{
               "actor1" => %{"species" => "woodpecker", "numSeen" => 2},
               "actor2" => %{"species" => "lapwing", "numSeen" => 2}
             }
    end

    test "should delete list elements" do
      actor = uuid()
      birds = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [
                  %{"action" => "insert", "index" => 0},
                  %{"action" => "insert", "index" => 1}
                ],
                "props" => %{
                  0 => %{"#{actor}" => %{"value" => "chaffinch"}},
                  1 => %{"#{actor}" => %{"value" => "goldfinch"}}
                }
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "birds" => %{
              "#{actor}" => %{
                "objectId" => birds,
                "type" => "list",
                "edits" => [%{"action" => "remove", "index" => 0}],
                "props" => %{}
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{"birds" => ["chaffinch", "goldfinch"]}
      assert Automerge.get_document(doc2) == %{"birds" => ["goldfinch"]}
    end

    test "should apply updates at different levels of the object tree" do
      counts = uuid()
      details = uuid()
      details1 = uuid()
      actor = uuid()

      patch1 = %{
        "clock" => %{"#{actor}" => 1},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "counts" => %{
              "#{actor}" => %{
                "objectId" => counts,
                "type" => "map",
                "props" => %{"magpies" => %{"#{actor}" => %{"value" => 2}}}
              }
            },
            "details" => %{
              "#{actor}" => %{
                "objectId" => details,
                "type" => "list",
                "edits" => [%{"action" => "insert", "index" => 0}],
                "props" => %{
                  0 => %{
                    "#{actor}" => %{
                      "objectId" => details1,
                      "type" => "map",
                      "props" => %{
                        "species" => %{"#{actor}" => %{"value" => "magpie"}},
                        "family" => %{"#{actor}" => %{"value" => "corvidae"}}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      patch2 = %{
        "clock" => %{"#{actor}" => 2},
        "diffs" => %{
          "objectId" => "_root",
          "type" => "map",
          "props" => %{
            "counts" => %{
              "#{actor}" => %{
                "objectId" => counts,
                "type" => "map",
                "props" => %{"magpies" => %{"#{actor}" => %{"value" => 3}}}
              }
            },
            "details" => %{
              "#{actor}" => %{
                "objectId" => details,
                "type" => "list",
                "edits" => [],
                "props" => %{
                  0 => %{
                    "#{actor}" => %{
                      "objectId" => details1,
                      "type" => "map",
                      "props" => %{
                        "species" => %{"#{actor}" => %{"value" => "Eurasian magpie"}}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      doc1 = Frontend.apply_patch!(Frontend.init(), patch1)
      doc2 = Frontend.apply_patch!(doc1, patch2)

      assert Automerge.get_document(doc1) == %{
               "counts" => %{"magpies" => 2},
               "details" => [%{"species" => "magpie", "family" => "corvidae"}]
             }

      assert Automerge.get_document(doc2) == %{
               "counts" => %{"magpies" => 3},
               "details" => [%{"species" => "Eurasian magpie", "family" => "corvidae"}]
             }
    end
  end
end
