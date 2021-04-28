defmodule Automerge.Frontend.DocumentTest do
  use Automerge.HelperCase, async: true

  alias Automerge.Frontend.Context

  @root_id "_root"

  def apply_patch(context, patch, _updated) do
    send(self(), {:patch, patch})

    context
  end

  describe "set_map_key/4" do
    setup do
      [
        context: %Context{
          max_op: 0,
          actor_id: uuid(),
          cache: %{@root_id => %Automerge.Map{_object_id: @root_id, _value: %{}}},
          apply_patch: &apply_patch/3
        }
      ]
    end

    test "should assign a primitive value to a map key", %{context: context} do
      context = Context.set_map_key!(context, [], "sparrows", 5)

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "sparrows" => %{"1@#{context.actor_id}" => %{"value" => 5}}
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "sparrows",
                 "obj" => "_root",
                 "pred" => [],
                 "value" => 5
               }
             ]
    end

    test "should do nothing if the value was not changed", %{context: context} do
      context = %{
        context
        | cache: %{
            @root_id => %Automerge.Map{
              _object_id: @root_id,
              _value: %{"goldfinches" => 3, _conflicts: %{"1@actor1" => 3}}
            }
          }
      }

      context = Context.set_map_key!(context, [], "goldfinches", 3)

      refute_receive {:patch, _}

      assert context.ops == []
    end

    test "should allow a conflict to be resolved", %{context: context} do
      context = %{
        context
        | cache: %{
            @root_id => %Automerge.Map{
              _object_id: @root_id,
              _value: %{"goldfinches" => 5, _conflicts: %{"1@actor1" => 3, "2@actor2" => 5}}
            }
          }
      }

      context = Context.set_map_key!(context, [], "goldfinches", 3)

      #      refute_receive {:patch, _}

      assert context.ops == [
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "goldfinches",
                 "obj" => "_root",
                 "pred" => [],
                 "value" => 3
               }
             ]
    end

    test "should create nested maps", %{context: context} do
      context = Context.set_map_key!(context, [], "birds", %{"goldfinches" => 3})

      receive do
        {:patch, patch} ->
          object_id = Enum.at(Map.keys(get_in(patch, ["props", "birds"])), 0)

          assert match?(patch, %{
                   "birds" => %{
                     "1@actor1" => %{
                       "objectId" => object_id,
                       "props" => %{
                         "goldfinches" => %{
                           "1@#{context.actor_id}" => %{"value" => 3}
                         }
                       },
                       "type" => "map"
                     }
                   }
                 })

          assert context.ops == [
                   %{
                     "action" => "makeMap",
                     "insert" => false,
                     "key" => "birds",
                     "obj" => "_root",
                     "pred" => []
                   },
                   %{
                     "action" => "set",
                     "insert" => false,
                     "key" => "goldfinches",
                     "obj" => object_id,
                     "pred" => [],
                     "value" => 3
                   }
                 ]
      end
    end

    test "should perform assignment inside nested maps", %{context: context} do
      object_id = uuid()
      child = %Automerge.Map{_object_id: object_id}

      root = %Automerge.Map{
        _object_id: @root_id,
        _conflicts: %{"birds" => %{"1@actor1" => child}},
        _value: %{"birds" => child}
      }

      context = %{context | cache: %{@root_id => root, object_id => child}}

      context =
        Context.set_map_key!(context, [%{key: "birds", object_id: object_id}], "goldfinches", 3)

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => object_id,
              "props" => %{
                "goldfinches" => %{
                  "1@#{context.actor_id}" => %{"value" => 3}
                }
              },
              "type" => "map"
            }
          }
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "goldfinches",
                 "obj" => object_id,
                 "pred" => [],
                 "value" => 3
               }
             ]
    end

    test "should perform assignment inside conflicted maps", %{context: context} do
      object_id1 = uuid()
      object_id2 = uuid()
      child1 = %Automerge.Map{_object_id: object_id1}
      child2 = %Automerge.Map{_object_id: object_id2}

      root = %Automerge.Map{
        _object_id: @root_id,
        _conflicts: %{"birds" => %{"1@actor1" => child1, "1@actor2" => child2}},
        _value: %{"birds" => child2}
      }

      context = %{
        context
        | cache: %{@root_id => root, object_id1 => child1, object_id2 => child2}
      }

      context =
        Context.set_map_key!(context, [%{key: "birds", object_id: object_id2}], "goldfinches", 3)

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => object_id1,
              "type" => "map"
            },
            "1@actor2" => %{
              "objectId" => object_id2,
              "props" => %{
                "goldfinches" => %{
                  "1@#{context.actor_id}" => %{"value" => 3}
                }
              },
              "type" => "map"
            }
          }
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "goldfinches",
                 "obj" => object_id2,
                 "pred" => [],
                 "value" => 3
               }
             ]
    end

    test "should handle conflict values of various types"

    test "should create nested lists", %{context: context} do
      context =
        Context.set_map_key!(context, [], "birds", Automerge.list(["sparrow", "goldfinch"]))

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "birds" => %{
            "1@#{context.actor_id}" => %{
              "edits" => [
                %{
                  "action" => "insert",
                  "elemId" => "2@#{context.actor_id}",
                  "index" => 0
                },
                %{
                  "action" => "insert",
                  "elemId" => "3@#{context.actor_id}",
                  "index" => 1
                }
              ],
              "objectId" => "1@#{context.actor_id}",
              "props" => %{
                0 => %{"2@#{context.actor_id}" => %{"value" => "sparrow"}},
                1 => %{"3@#{context.actor_id}" => %{"value" => "goldfinch"}}
              },
              "type" => "list"
            }
          }
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "makeList",
                 "insert" => false,
                 "key" => "birds",
                 "obj" => "_root",
                 "pred" => []
               },
               %{
                 "action" => "set",
                 "elemId" => "_head",
                 "insert" => true,
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "sparrow"
               },
               %{
                 "action" => "set",
                 "elemId" => "2@#{context.actor_id}",
                 "insert" => true,
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "goldfinch"
               }
             ]
    end

    test "should create nested Text objects"

    test "should create nested Table objects"

    test "should allow assignment of Date values"

    test "should allow assignment of Counter values"
  end

  describe "delete_map_key/3" do
    setup do
      [
        context: %Context{
          max_op: 0,
          actor_id: uuid(),
          cache: %{@root_id => %Automerge.Map{_object_id: @root_id, _value: %{}}},
          apply_patch: &apply_patch/3
        }
      ]
    end

    test "should remove an existing key", %{context: context} do
      context = %{
        context
        | cache: %{
            @root_id => %Automerge.Map{
              _object_id: @root_id,
              _conflicts: %{"goldfinches" => %{"1@actor1" => 3}},
              _value: %{"goldfinches" => 3}
            }
          }
      }

      context = Context.delete_map_key(context, [], "goldfinches")

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "goldfinches" => %{}
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "del",
                 "insert" => false,
                 "key" => "goldfinches",
                 "obj" => "_root",
                 "pred" => ["1@actor1"]
               }
             ]
    end

    test "should do nothing if the key does not exist", %{context: context} do
      context = %{
        context
        | cache: %{
            @root_id => %Automerge.Map{
              _object_id: @root_id,
              _value: %{"goldfinches" => 3, _conflicts: %{"goldfinches" => %{"1@actor1" => 3}}}
            }
          }
      }

      context = Context.delete_map_key(context, [], "sparrows")

      assert context.ops == []
    end

    test "should update a nested object", %{context: context} do
      object_id = uuid()

      child = %Automerge.Map{
        _object_id: object_id,
        _conflicts: %{"goldfinches" => %{"5@actor1" => 3}},
        _value: %{"goldfinches" => 3}
      }

      root = %Automerge.Map{
        _object_id: @root_id,
        _conflicts: %{"birds" => %{"1@actor1" => child}},
        _value: %{"birds" => child}
      }

      context = %{context | cache: %{@root_id => root, object_id => child}}

      context =
        Context.delete_map_key(context, [%{key: "birds", object_id: object_id}], "goldfinches")

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => object_id,
              "type" => "map",
              "props" => %{"goldfinches" => %{}}
            }
          }
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "del",
                 "insert" => false,
                 "key" => "goldfinches",
                 "obj" => object_id,
                 "pred" => ["5@actor1"]
               }
             ]
    end
  end

  describe "modify lists" do
    setup do
      list_id = uuid()
      list = Automerge.list(["swallow", "magpie"])

      list = %{
        list
        | _object_id: list_id,
          _conflicts: %{0 => %{"1@xxx" => "swallow"}, 1 => %{"2@xxx" => "magpie"}},
          _elem_ids: ["1@xxx", "2@xxx"]
      }

      root = %Automerge.Map{
        _object_id: @root_id,
        _value: %{"birds" => list},
        _conflicts: %{"birds" => %{"1@actor1" => list}}
      }

      [
        list_id: list_id,
        context: %Context{
          max_op: 0,
          actor_id: uuid(),
          cache: %{@root_id => root, list_id => list},
          apply_patch: &apply_patch/3
        }
      ]
    end

    test "should overwrite an existing list element", %{context: context, list_id: list_id} do
      context =
        Context.set_list_index(context, [%{key: "birds", object_id: list_id}], 0, "starling")

      patch = %{
        "objectId" => "_root",
        "type" => "map",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => list_id,
              "type" => "list",
              "props" => %{
                0 => %{"1@#{context.actor_id}" => %{"value" => "starling"}}
              }
            }
          }
        }
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "set",
                 "elemId" => "1@xxx",
                 "insert" => false,
                 "obj" => list_id,
                 "pred" => ["1@xxx"],
                 "value" => "starling"
               }
             ]
    end

    test "should create nested objects on assignment", %{context: context, list_id: list_id} do
      context =
        Context.set_list_index(context, [%{key: "birds", object_id: list_id}], 1, %{
          "english" => "goldfinch",
          "latin" => "carduelis"
        })

      patch = %{
        "objectId" => "_root",
        "type" => "map",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => list_id,
              "type" => "list",
              "props" => %{
                1 => %{
                  "1@#{context.actor_id}" => %{
                    "objectId" => "1@#{context.actor_id}",
                    "type" => "map",
                    "props" => %{
                      "english" => %{
                        "2@#{context.actor_id}" => %{"value" => "goldfinch"}
                      },
                      "latin" => %{
                        "3@#{context.actor_id}" => %{"value" => "carduelis"}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "makeMap",
                 "elemId" => "2@xxx",
                 "insert" => false,
                 "obj" => list_id,
                 "pred" => ["2@xxx"]
               },
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "english",
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "goldfinch"
               },
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "latin",
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "carduelis"
               }
             ]
    end

    test "should create nested objects on insertion", %{context: context, list_id: list_id} do
      context =
        Context.splice(context, [%{key: "birds", object_id: list_id}], 2, 0, [
          %{"english" => "goldfinch", "latin" => "carduelis"}
        ])

      map_id = Map.get(hd(context.ops), "obj")

      patch = %{
        "objectId" => "_root",
        "type" => "map",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => list_id,
              "type" => "list",
              "edits" => [
                %{"action" => "insert", "index" => 2, "elemId" => "1@#{context.actor_id}"}
              ],
              "props" => %{
                2 => %{
                  "1@#{context.actor_id}" => %{
                    "objectId" => "1@#{context.actor_id}",
                    "type" => "map",
                    "props" => %{
                      "english" => %{
                        "2@#{context.actor_id}" => %{"value" => "goldfinch"}
                      },
                      "latin" => %{
                        "3@#{context.actor_id}" => %{"value" => "carduelis"}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "makeMap",
                 "elemId" => "2@xxx",
                 "insert" => true,
                 "obj" => map_id,
                 "pred" => []
               },
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "english",
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "goldfinch"
               },
               %{
                 "action" => "set",
                 "insert" => false,
                 "key" => "latin",
                 "obj" => "1@#{context.actor_id}",
                 "pred" => [],
                 "value" => "carduelis"
               }
             ]
    end

    test "should support deleting list elements", %{context: context, list_id: list_id} do
      context = Context.splice(context, [%{key: "birds", object_id: list_id}], 0, 2, [])

      patch = %{
        "objectId" => "_root",
        "type" => "map",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "objectId" => list_id,
              "type" => "list",
              "props" => %{},
              "edits" => [
                %{"action" => "remove", "index" => 0},
                %{"action" => "remove", "index" => 0}
              ]
            }
          }
        }
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "del",
                 "elemId" => "1@xxx",
                 "insert" => false,
                 "obj" => list_id,
                 "pred" => ["1@xxx"]
               },
               %{
                 "action" => "del",
                 "elemId" => "2@xxx",
                 "insert" => false,
                 "obj" => list_id,
                 "pred" => ["2@xxx"]
               }
             ]
    end

    test "should support list splicing", %{context: context, list_id: list_id} do
      context =
        Context.splice(context, [%{key: "birds", object_id: list_id}], 0, 1, [
          "starling",
          "goldfinch"
        ])

      patch = %{
        "objectId" => "_root",
        "props" => %{
          "birds" => %{
            "1@actor1" => %{
              "edits" => [
                %{"action" => "remove", "index" => 0},
                %{
                  "action" => "insert",
                  "elemId" => "2@#{context.actor_id}",
                  "index" => 0
                },
                %{
                  "action" => "insert",
                  "elemId" => "3@#{context.actor_id}",
                  "index" => 1
                }
              ],
              "objectId" => list_id,
              "props" => %{
                0 => %{"2@#{context.actor_id}" => %{"value" => "starling"}},
                1 => %{"3@#{context.actor_id}" => %{"value" => "goldfinch"}}
              },
              "type" => "list"
            }
          }
        },
        "type" => "map"
      }

      assert_receive {:patch, ^patch}

      assert context.ops == [
               %{
                 "action" => "del",
                 "elemId" => "1@xxx",
                 "insert" => false,
                 "obj" => list_id,
                 "pred" => ["1@xxx"]
               },
               %{
                 "action" => "set",
                 "elemId" => "_head",
                 "insert" => true,
                 "obj" => list_id,
                 "pred" => [],
                 "value" => "starling"
               },
               %{
                 "action" => "set",
                 "elemId" => "2@#{context.actor_id}",
                 "insert" => true,
                 "obj" => list_id,
                 "pred" => [],
                 "value" => "goldfinch"
               }
             ]
    end
  end
end
