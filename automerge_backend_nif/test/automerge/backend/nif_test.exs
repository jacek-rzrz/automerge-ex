defmodule Automerge.Backend.NIFTest do
  use ExUnit.Case, async: true

  alias Automerge.Backend.NIF, as: Backend

  defp uuid(), do: UUID.uuid4(:hex)

  defp hash(change) do
    change
    |> Backend.encode_change()
    |> Backend.decode_change()
    |> Map.get("hash")
  end

  defp now(), do: DateTime.now!("Etc/UTC") |> DateTime.to_unix()

  describe "init/0" do
    test "Empty" do
      ref = Backend.init()
      assert is_reference(ref) == true
    end
  end

  test "save/1" do
    empty_backend = Backend.init()

    assert Backend.save(empty_backend) == [133, 111, 74, 131, 184, 26, 149, 68, 0, 4, 0, 0, 0, 0]
  end

  describe "apply_changes/2" do
    test "should assign to a key in a map" do
      actor = uuid()

      backend = Backend.init()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      {_backend, patch1} = Backend.apply_changes(backend, [Backend.encode_change(change1)])

      assert patch1 == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{"1@#{actor}" => %{"value" => "magpie"}}
                 },
                 "type" => "map"
               },
               "maxOp" => 1
             }
    end

    test "should increment a key in a map" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "counter",
            "value" => 1,
            "datatype" => "counter",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "inc",
            "obj" => "_root",
            "key" => "counter",
            "value" => 2,
            "pred" => ["1@#{actor}"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "counter" => %{"1@#{actor}" => %{"value" => 3, "datatype" => "counter"}}
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should make a conflict on assignment to the same key" do
      change1 = %{
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => "222222",
        "seq" => 1,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "blackbird",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{
                 "111111" => 1,
                 "222222" => 1
               },
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{
                     "1@111111" => %{
                       "value" => "magpie"
                     },
                     "2@222222" => %{
                       "value" => "blackbird"
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should delete a key from a map" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{"action" => "del", "obj" => "_root", "key" => "bird", "pred" => ["1@#{actor}"]}
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{}
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should create nested maps" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeMap", "obj" => "_root", "key" => "bird", "pred" => []},
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "key" => "wrens",
            "value" => 3,
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {_s1, patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])

      assert patch1 == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "map",
                       "props" => %{
                         "wrens" => %{"2@#{actor}" => %{"value" => 3}}
                       }
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should assign to keys in nested maps" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeMap", "obj" => "_root", "key" => "bird", "pred" => []},
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "key" => "wrens",
            "value" => 3,
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "key" => "sparrows",
            "value" => 15,
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "map",
                       "props" => %{
                         "sparrows" => %{"3@#{actor}" => %{"value" => 15}}
                       }
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end

    test "should create lists" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeList", "obj" => "_root", "key" => "bird", "pred" => []},
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {_s1, patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])

      assert patch1 == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "props" => %{
                         "0" => %{"2@#{actor}" => %{"value" => "chaffinch"}}
                       },
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "elemId" => "2@#{actor}", "index" => 0}
                       ]
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should apply updates inside lists" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeList", "obj" => "_root", "key" => "birds", "pred" => []},
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "value" => "greenfinch",
            "pred" => ["2@#{actor}"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "props" => %{
                         "0" => %{"3@#{actor}" => %{"value" => "greenfinch"}}
                       },
                       "type" => "list",
                       "edits" => []
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end

    test "should delete list elements" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeList", "obj" => "_root", "key" => "birds", "pred" => []},
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "del",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "pred" => ["2@#{actor}"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "props" => %{},
                       "type" => "list",
                       "edits" => [%{"action" => "remove", "index" => 0}]
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end

    test "should handle list element insertion and deletion in the same change" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeList", "obj" => "_root", "key" => "birds", "pred" => []}
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          },
          %{
            "action" => "del",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "pred" => ["2@#{actor}"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {_s2, patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])

      assert patch2 == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "props" => %{},
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "2@#{actor}"},
                         %{"action" => "remove", "index" => 0}
                       ]
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end

    test "should handle changes within conflicted objects" do
      actor1 = uuid()
      actor2 = uuid()

      change1 = %{
        "actor" => actor1,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeList", "obj" => "_root", "key" => "conflict", "pred" => []}
        ]
      }

      change2 = %{
        "actor" => actor2,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{"action" => "makeMap", "obj" => "_root", "key" => "conflict", "pred" => []}
        ]
      }

      change3 = %{
        "actor" => actor2,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change2)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@#{actor2}",
            "key" => "sparrows",
            "value" => 12,
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {s2, _patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])
      {_s3, patch3} = Backend.apply_changes(s2, [Backend.encode_change(change3)])

      assert patch3 == %{
               "clock" => %{"#{actor1}" => 1, "#{actor2}" => 2},
               "deps" => Enum.sort([hash(change1), hash(change3)]),
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "conflict" => %{
                     "1@#{actor1}" => %{"objectId" => "1@#{actor1}", "type" => "list"},
                     "1@#{actor2}" => %{
                       "objectId" => "1@#{actor2}",
                       "type" => "map",
                       "props" => %{"sparrows" => %{"2@#{actor2}" => %{"value" => 12}}}
                     }
                   }
                 }
               },
               "maxOp" => 2
             }
    end

    test "should support Date objects at the root" do
      now = now()
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "now",
            "value" => now,
            "datatype" => "timestamp",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {_s1, patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])

      assert patch1 == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "now" => %{
                     "1@#{actor}" => %{"value" => now, "datatype" => "timestamp"}
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 1
             }
    end

    test "should support Date objects in a list'" do
      now = now()
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "list",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => now,
            "datatype" => "timestamp",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {_s1, patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])

      assert patch1 == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "list" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "2@#{actor}"}
                       ],
                       "props" => %{
                         "0" => %{"2@#{actor}" => %{"value" => now, "datatype" => "timestamp"}}
                       }
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }
    end

    test "should handle updates to an object that has been deleted" do
      actor1 = uuid()
      actor2 = uuid()

      change1 = %{
        "actor" => actor1,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeMap",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor1}",
            "key" => "blackbirds",
            "value" => 2,
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor2,
        "seq" => 1,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{"action" => "del", "obj" => "_root", "key" => "birds", "pred" => ["1@#{actor1}"]}
        ]
      }

      change3 = %{
        "actor" => actor1,
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@#{actor1}",
            "key" => "blackbirds",
            "value" => 2,
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(change1)])
      {s2, _patch2} = Backend.apply_changes(s1, [Backend.encode_change(change2)])
      {_s3, patch3} = Backend.apply_changes(s2, [Backend.encode_change(change3)])

      assert patch3 == %{
               "clock" => %{"#{actor1}" => 2, "#{actor2}" => 1},
               "deps" => Enum.sort([hash(change2), hash(change3)]),
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end
  end

  describe "apply_local_change/2" do
    test "should apply change requests" do
      change1 = %{
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, patch1, _bin_change} = Backend.apply_local_change(s0, change1)
      changes01 = s1 |> Backend.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert patch1 == %{
               "actor" => "111111",
               "seq" => 1,
               "clock" => %{"111111" => 1},
               "deps" => [],
               "maxOp" => 1,
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "bird" => %{"1@111111" => %{"value" => "magpie"}}
                 }
               }
             }

      assert changes01 == [
               %{
                 "hash" => "2c2845859ce4336936f56410f9161a09ba269f48aee5826782f1c389ec01d054",
                 "actor" => "111111",
                 "seq" => 1,
                 "startOp" => 1,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [],
                 "ops" => [
                   %{
                     "action" => "set",
                     "obj" => "_root",
                     "key" => "bird",
                     "value" => "magpie",
                     "pred" => []
                   }
                 ]
               }
             ]
    end

    test "should throw an exception on duplicate requests" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "jay",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1, _bin_change} = Backend.apply_local_change(s0, change1)
      {s2, _patch2, _bin_change} = Backend.apply_local_change(s1, change2)

      assert_raise ErlangError, fn ->
        Backend.apply_local_change(s2, change1)
      end

      assert_raise ErlangError, fn ->
        Backend.apply_local_change(s2, change2)
      end
    end

    test "should handle frontend and backend changes happening concurrently" do
      local1 = %{
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      local2 = %{
        "actor" => "111111",
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "jay",
            "pred" => ["1@111111"]
          }
        ]
      }

      remote1 = %{
        "actor" => "222222",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "fish",
            "value" => "goldfish",
            "pred" => []
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1, _bin_change} = Backend.apply_local_change(s0, local1)
      {s2, _patch2} = Backend.apply_changes(s1, [Backend.encode_change(remote1)])
      {s3, _patch3, _bin_change} = Backend.apply_local_change(s2, local2)

      changes = s3 |> Backend.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert changes == [
               %{
                 "hash" => "2c2845859ce4336936f56410f9161a09ba269f48aee5826782f1c389ec01d054",
                 "actor" => "111111",
                 "seq" => 1,
                 "startOp" => 1,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [],
                 "ops" => [
                   %{
                     "action" => "set",
                     "obj" => "_root",
                     "key" => "bird",
                     "value" => "magpie",
                     "pred" => []
                   }
                 ]
               },
               %{
                 "hash" => "efc7e9b1b809364fb1b7029d2838dd3c7cf539eea595b22f9ae665505187f6c4",
                 "actor" => "222222",
                 "seq" => 1,
                 "startOp" => 1,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [],
                 "ops" => [
                   %{
                     "action" => "set",
                     "obj" => "_root",
                     "key" => "fish",
                     "value" => "goldfish",
                     "pred" => []
                   }
                 ]
               },
               %{
                 "hash" => "e7ed7a790432aba39fe7ad75fa9e02a9fc8d8e9ee4ec8c81dcc93da15a561f8a",
                 "actor" => "111111",
                 "seq" => 2,
                 "startOp" => 2,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [get_in(changes, [Access.at(0), "hash"])],
                 "ops" => [
                   %{
                     "action" => "set",
                     "obj" => "_root",
                     "key" => "bird",
                     "value" => "jay",
                     "pred" => ["1@111111"]
                   }
                 ]
               }
             ]
    end

    test "should detect conflicts based on the frontend version" do
      local1 = %{
        "requestType" => "change",
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "goldfinch",
            "pred" => []
          }
        ]
      }

      local2 = %{
        "requestType" => "change",
        "actor" => "111111",
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "jay",
            "pred" => ["1@111111"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1, _bin_change} = Backend.apply_local_change(s0, local1)

      local1_hash =
        s1
        |> Backend.get_all_changes()
        |> Enum.map(&Backend.decode_change/1)
        |> get_in([Access.at(0), "hash"])

      remote1 = %{
        "actor" => "222222",
        "seq" => 1,
        "startOp" => 2,
        "time" => 0,
        "deps" => [local1_hash],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => ["1@111111"]
          }
        ]
      }

      {s2, _patch2} = Backend.apply_changes(s1, [Backend.encode_change(remote1)])
      {s3, patch3, _bin_change} = Backend.apply_local_change(s2, local2)

      changes = s3 |> Backend.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert patch3 == %{
               "actor" => "111111",
               "seq" => 2,
               "clock" => %{"111111" => 2, "222222" => 1},
               "deps" => [hash(remote1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "bird" => %{
                     "2@222222" => %{"value" => "magpie"},
                     "2@111111" => %{"value" => "jay"}
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 2
             }

      assert get_in(changes, [Access.at(2)]) == %{
               "hash" => "7a00e28d7fbf179708a1b0045c7f9bad93366c0e69f9af15e830dae9970a9d19",
               "actor" => "111111",
               "seq" => 2,
               "startOp" => 2,
               "time" => 0,
               "message" => nil,
               "deps" => [get_in(changes, [Access.at(0), "hash"])],
               "ops" => [
                 %{
                   "action" => "set",
                   "obj" => "_root",
                   "key" => "bird",
                   "value" => "jay",
                   "pred" => ["1@111111"]
                 }
               ]
             }
    end

    test "should transform list indexes into element IDs" do
      remote1 = %{
        "actor" => "222222",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          }
        ]
      }

      remote2 = %{
        "actor" => "222222",
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(remote1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@222222",
            "elemId" => "_head",
            "insert" => true,
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      local1 = %{
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(remote1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@222222",
            "elemId" => "_head",
            "insert" => true,
            "value" => "goldfinch",
            "pred" => []
          }
        ]
      }

      local2 = %{
        "actor" => "111111",
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@222222",
            "elemId" => "2@111111",
            "insert" => true,
            "value" => "wagtail",
            "pred" => []
          }
        ]
      }

      local3 = %{
        "actor" => "111111",
        "seq" => 3,
        "startOp" => 4,
        "time" => 0,
        "deps" => [hash(remote2)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@222222",
            "elemId" => "2@222222",
            "value" => "Magpie",
            "pred" => ["2@222222"]
          },
          %{
            "action" => "set",
            "obj" => "1@222222",
            "elemId" => "2@111111",
            "value" => "Goldfinch",
            "pred" => ["2@111111"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1} = Backend.apply_changes(s0, [Backend.encode_change(remote1)])
      {s2, _patch2, _bin_change} = Backend.apply_local_change(s1, local1)
      {s3, _patch3} = Backend.apply_changes(s2, [Backend.encode_change(remote2)])
      {s4, _patch4, _bin_change} = Backend.apply_local_change(s3, local2)
      {s5, _patch5, _bin_change} = Backend.apply_local_change(s4, local3)

      changes = s5 |> Backend.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert get_in(changes, [Access.at(1)]) == %{
               "hash" => "06392148c4a0dfff8b346ad58a3261cc15187cbf8a58779f78d54251126d4ccc",
               "actor" => "111111",
               "seq" => 1,
               "startOp" => 2,
               "time" => 0,
               "message" => nil,
               "deps" => [hash(remote1)],
               "ops" => [
                 %{
                   "action" => "set",
                   "obj" => "1@222222",
                   "elemId" => "_head",
                   "insert" => true,
                   "value" => "goldfinch",
                   "pred" => []
                 }
               ]
             }

      assert get_in(changes, [Access.at(3)]) == %{
               "hash" => "2801c386ec2a140376f3bef285a6e6d294a2d8fb7a180da4fbb6e2bc4f550dd9",
               "actor" => "111111",
               "seq" => 2,
               "startOp" => 3,
               "time" => 0,
               "message" => nil,
               "deps" => [get_in(changes, [Access.at(1), "hash"])],
               "ops" => [
                 %{
                   "action" => "set",
                   "obj" => "1@222222",
                   "elemId" => "2@111111",
                   "insert" => true,
                   "value" => "wagtail",
                   "pred" => []
                 }
               ]
             }

      assert get_in(changes, [Access.at(4)]) == %{
               "hash" => "734f1dad5fb2f10970bae2baa6ce100c3b85b43072b3799d8f2e15bcd21297fc",
               "actor" => "111111",
               "seq" => 3,
               "startOp" => 4,
               "time" => 0,
               "message" => nil,
               "deps" => Enum.sort([hash(remote2), get_in(changes, [Access.at(3), "hash"])]),
               "ops" => [
                 %{
                   "action" => "set",
                   "obj" => "1@222222",
                   "elemId" => "2@222222",
                   "value" => "Magpie",
                   "pred" => ["2@222222"]
                 },
                 %{
                   "action" => "set",
                   "obj" => "1@222222",
                   "elemId" => "2@111111",
                   "value" => "Goldfinch",
                   "pred" => ["2@111111"]
                 }
               ]
             }
    end

    test "should handle list element insertion and deletion in the same change" do
      local1 = %{
        "requestType" => "change",
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          }
        ]
      }

      local2 = %{
        "requestType" => "change",
        "actor" => "111111",
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "1@111111",
            "elemId" => "_head",
            "insert" => true,
            "value" => "magpie",
            "pred" => []
          },
          %{
            "action" => "del",
            "obj" => "1@111111",
            "elemId" => "2@111111",
            "pred" => ["2@111111"]
          }
        ]
      }

      s0 = Backend.init()

      {s1, _patch1, _bin_change} = Backend.apply_local_change(s0, local1)
      {s2, patch2, _bin_change} = Backend.apply_local_change(s1, local2)

      changes = s2 |> Backend.get_all_changes() |> Enum.map(&Backend.decode_change/1)

      assert patch2 == %{
               "actor" => "111111",
               "seq" => 2,
               "clock" => %{"111111" => 2},
               "deps" => [],
               "maxOp" => 3,
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "birds" => %{
                     "1@111111" => %{
                       "objectId" => "1@111111",
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "2@111111"},
                         %{"action" => "remove", "index" => 0}
                       ],
                       "props" => %{}
                     }
                   }
                 }
               }
             }

      assert changes == [
               %{
                 "hash" => get_in(changes, [Access.at(0), "hash"]),
                 "actor" => "111111",
                 "seq" => 1,
                 "startOp" => 1,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [],
                 "ops" => [
                   %{
                     "action" => "makeList",
                     "obj" => "_root",
                     "key" => "birds",
                     "pred" => []
                   }
                 ]
               },
               %{
                 "hash" => "deef4c9b9ca378844144c4bbc5d82a52f30c95a8624f13f243fe8f1214e8e833",
                 "actor" => "111111",
                 "seq" => 2,
                 "startOp" => 2,
                 "time" => 0,
                 "message" => nil,
                 "deps" => [get_in(changes, [Access.at(0), "hash"])],
                 "ops" => [
                   %{
                     "action" => "set",
                     "obj" => "1@111111",
                     "elemId" => "_head",
                     "insert" => true,
                     "value" => "magpie",
                     "pred" => []
                   },
                   %{
                     "action" => "del",
                     "obj" => "1@111111",
                     "elemId" => "2@111111",
                     "pred" => ["2@111111"]
                   }
                 ]
               }
             ]
    end
  end

  describe "get_patch/1" do
    test "should include the most recent value for a key" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "blackbird",
            "pred" => ["1@#{actor}"]
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "bird" => %{
                     "2@#{actor}" => %{"value" => "blackbird"}
                   }
                 }
               },
               "maxOp" => 2
             }
    end

    test "should include conflicting values for a key" do
      change1 = %{
        "actor" => "111111",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "magpie",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => "222222",
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "bird",
            "value" => "blackbird",
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"111111" => 1, "222222" => 1},
               "deps" => Enum.sort([hash(change1), hash(change2)]),
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "bird" => %{
                     "1@111111" => %{"value" => "magpie"},
                     "1@222222" => %{"value" => "blackbird"}
                   }
                 }
               },
               "maxOp" => 1
             }
    end

    test "should handle counter increments at a key in a map" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "counter",
            "value" => 1,
            "datatype" => "counter",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "inc",
            "obj" => "_root",
            "key" => "counter",
            "value" => 2,
            "pred" => ["1@#{actor}"]
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "counter" => %{
                     "1@#{actor}" => %{"value" => 3, "datatype" => "counter"}
                   }
                 }
               },
               "maxOp" => 2
             }
    end

    test "should handle deletion of a counter" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "counter",
            "value" => 1,
            "datatype" => "counter",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 2,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "inc",
            "obj" => "_root",
            "key" => "counter",
            "value" => 2,
            "pred" => ["1@#{actor}"]
          }
        ]
      }

      change3 = %{
        "actor" => actor,
        "seq" => 3,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change2)],
        "ops" => [
          %{
            "action" => "del",
            "obj" => "_root",
            "key" => "counter",
            "pred" => ["1@#{actor}"]
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2, change3], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 3},
               "deps" => [hash(change3)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map"
               },
               "maxOp" => 3
             }
    end

    test "should create nested maps" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeMap",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "key" => "wrens",
            "value" => 3,
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 3,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "del",
            "obj" => "1@#{actor}",
            "key" => "wrens",
            "pred" => ["2@#{actor}"]
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "key" => "sparrows",
            "value" => 15,
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "map",
                       "props" => %{
                         "sparrows" => %{
                           "4@#{actor}" => %{"value" => 15}
                         }
                       }
                     }
                   }
                 }
               },
               "maxOp" => 4
             }
    end

    test "should create lists" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change1)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "2@#{actor}"}
                       ],
                       "props" => %{"0" => %{"2@#{actor}" => %{"value" => "chaffinch"}}}
                     }
                   }
                 }
               },
               "maxOp" => 2
             }
    end

    test "should include the latest state of a list" do
      actor = uuid()

      change1 = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "birds",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => "chaffinch",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "insert" => true,
            "value" => "goldfinch",
            "pred" => []
          }
        ]
      }

      change2 = %{
        "actor" => actor,
        "seq" => 2,
        "startOp" => 4,
        "time" => 0,
        "deps" => [hash(change1)],
        "ops" => [
          %{
            "action" => "del",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "pred" => ["2@#{actor}"]
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "2@#{actor}",
            "insert" => true,
            "value" => "greenfinch",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "3@#{actor}",
            "value" => "goldfinches!!",
            "pred" => ["3@#{actor}"]
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change1, change2], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 2},
               "deps" => [hash(change2)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "birds" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "5@#{actor}"},
                         %{"action" => "insert", "index" => 1, "elemId" => "3@#{actor}"}
                       ],
                       "props" => %{
                         "0" => %{"5@#{actor}" => %{"value" => "greenfinch"}},
                         "1" => %{"6@#{actor}" => %{"value" => "goldfinches!!"}}
                       }
                     }
                   }
                 }
               },
               "maxOp" => 6
             }
    end

    test "should handle nested maps in lists" do
      actor = uuid()

      change = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "todos",
            "pred" => []
          },
          %{
            "action" => "makeMap",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "2@#{actor}",
            "key" => "title",
            "value" => "water plants",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "2@#{actor}",
            "key" => "done",
            "value" => false,
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change)],
               "diffs" => %{
                 "objectId" => "_root",
                 "props" => %{
                   "todos" => %{
                     "1@#{actor}" => %{
                       "edits" => [
                         %{
                           "action" => "insert",
                           "elemId" => "2@#{actor}",
                           "index" => 0
                         }
                       ],
                       "objectId" => "1@#{actor}",
                       "props" => %{
                         "0" => %{
                           "2@#{actor}" => %{
                             "objectId" => "2@#{actor}",
                             "props" => %{
                               "done" => %{
                                 "4@#{actor}" => %{"value" => false}
                               },
                               "title" => %{
                                 "3@#{actor}" => %{
                                   "value" => "water plants"
                                 }
                               }
                             },
                             "type" => "map"
                           }
                         }
                       },
                       "type" => "list"
                     }
                   }
                 },
                 "type" => "map"
               },
               "maxOp" => 4
             }
    end

    test "should include Date objects at the root" do
      now = now()
      actor = uuid()

      change = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "set",
            "obj" => "_root",
            "key" => "now",
            "value" => now,
            "datatype" => "timestamp",
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "now" => %{"1@#{actor}" => %{"value" => now, "datatype" => "timestamp"}}
                 }
               },
               "maxOp" => 1
             }
    end

    test "should include Date objects in a list" do
      now = now()
      actor = uuid()

      change = %{
        "actor" => actor,
        "seq" => 1,
        "startOp" => 1,
        "time" => 0,
        "deps" => [],
        "ops" => [
          %{
            "action" => "makeList",
            "obj" => "_root",
            "key" => "list",
            "pred" => []
          },
          %{
            "action" => "set",
            "obj" => "1@#{actor}",
            "elemId" => "_head",
            "insert" => true,
            "value" => now,
            "datatype" => "timestamp",
            "pred" => []
          }
        ]
      }

      s1 =
        Backend.load_changes(
          Backend.init(),
          Enum.map([change], &Backend.encode_change/1)
        )

      assert Backend.get_patch(s1) == %{
               "clock" => %{"#{actor}" => 1},
               "deps" => [hash(change)],
               "diffs" => %{
                 "objectId" => "_root",
                 "type" => "map",
                 "props" => %{
                   "list" => %{
                     "1@#{actor}" => %{
                       "objectId" => "1@#{actor}",
                       "type" => "list",
                       "edits" => [
                         %{"action" => "insert", "index" => 0, "elemId" => "2@#{actor}"}
                       ],
                       "props" => %{
                         "0" => %{"2@#{actor}" => %{"value" => now, "datatype" => "timestamp"}}
                       }
                     }
                   }
                 }
               },
               "maxOp" => 2
             }
    end
  end
end
