defmodule Automerge.TextTest do
  use ExUnit.Case, async: true

  alias Automerge.Text

  def is_control_marker(char) when is_map(char) and is_map_key(char, "attributes"), do: true
  def is_control_marker(_char), do: false

  def automerge_text_to_delta_doc(text) do
    text
    |> Text.to_spans()
    |> Enum.reduce(fn span ->
      if is_control_marker(span) do
      end
    end)
  end

  def apply_delta_doc_to_automerge_text(delta, doc) do
    for op <- delta, reduce: {doc, 0} do
      {doc, offset} ->
        cond do
          op["insert"] -> {doc, offset}
        end
    end
  end

  describe "text" do
    setup do
      {s1, patch} = Automerge.change!(Automerge.init(), &put_in(&1["text"], Automerge.text()))
      s2 = Automerge.merge!(Automerge.init(), s1)

      [s1: s1, s2: s2]
    end

    test "should support insertion", %{s1: s1} do
      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.insert_at(text, 0, "a") end)
        )

      value = Automerge.get_document(s1)

      assert length(value["text"]) == 1
      assert get_in(value, ["text", Access.at(0)]) == "a"
      assert List.to_string(value["text"]) == "a"
    end

    test "should support deletion", %{s1: s1} do
      {s1, patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.insert_at(text, 0, ["a", "b", "c"]) end)
        )

      {s1, patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.delete_at(text, 1, 1) end)
        )

      value = Automerge.get_document(s1)

      assert length(value["text"]) == 2
      assert get_in(value, ["text", Access.at(0)]) == "a"
      assert get_in(value, ["text", Access.at(1)]) == "c"
      assert List.to_string(value["text"]) == "ac"
    end

    test "should support implicit and explicit deletion", %{s1: s1} do
      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.insert_at(text, 0, ["a", "b", "c"]) end)
        )

      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.delete_at(text, 1) end)
        )

      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.delete_at(text, 1, 0) end)
        )

      value = Automerge.get_document(s1)

      assert length(value["text"]) == 2
      assert get_in(value, ["text", Access.at(0)]) == "a"
      assert get_in(value, ["text", Access.at(1)]) == "c"
      assert to_string(value["text"]) == "ac"
    end

    test "should handle concurrent insertion", %{s1: s1, s2: s2} do
      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text -> Text.insert_at(text, 0, ["a", "b", "c"]) end)
        )

      {s2, _patch} =
        Automerge.change!(
          s2,
          &update_in(&1["text"], fn text -> Text.insert_at(text, 0, ["x", "y", "z"]) end)
        )

      s1 = Automerge.merge!(s1, s2)

      value = Automerge.get_document(s1)

      assert length(value["text"]) == 6
      assert to_string(value["text"]) in ["abcxyz", "xyzabc"]
    end

    test "should handle text and other ops in the same change", %{s1: s1} do
      {s1, _patch} =
        Automerge.change!(s1, fn doc ->
          doc
          |> put_in(["foo"], "bar")
          |> update_in(["text"], fn text -> Text.insert_at(text, 0, ["a"]) end)
        end)

      value = Automerge.get_document(s1)

      assert value["foo"] == "bar"

      assert to_string(value["text"]) == "a"
    end

    test "should serialize to JSON as a simple string"

    test "should allow modification before an object is assigned to a document" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          text = Automerge.text()

          text =
            text
            |> Text.insert_at(0, ["a", "b", "c", "d"])
            |> Text.delete_at(2)

          put_in(doc["text"], text)
        end)

      value = Automerge.get_document(s1)

      assert to_string(value["text"]) == "abd"
    end

    test "should allow modification after an object is assigned to a document" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          doc
          |> put_in(["text"], Automerge.text())
          |> update_in(["text"], &Automerge.Text.insert_at(&1, 0, ["a", "b", "c", "d"]))
          |> update_in(["text"], &Automerge.Text.delete_at(&1, 2))
        end)

      value = Automerge.get_document(s1)

      assert to_string(value["text"]) == "abd"
    end

    test "should not allow modification outside of a change callback", %{s1: s1} do
      assert_raise RuntimeError, "Cannot modify a list outside of a change callback", fn ->
        Text.insert_at(s1["text"], 0, ["a"])
      end
    end
  end

  describe "with initial value" do
    test "should accept a string as an initial value" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), &put_in(&1["text"], Automerge.text("init")))

      value = Automerge.get_document(s1)

      assert get_in(value, ["text", Access.at!(0)]) == "i"
      assert get_in(value, ["text", Access.at!(1)]) == "n"
      assert get_in(value, ["text", Access.at!(2)]) == "i"
      assert get_in(value, ["text", Access.at!(3)]) == "t"

      assert to_string(value["text"]) == "init"
    end

    test "should accept an array as initial value" do
      {s1, _patch} =
        Automerge.change!(
          Automerge.init(),
          &put_in(&1["text"], Automerge.text(["i", "n", "i", "t"]))
        )

      value = Automerge.get_document(s1)

      assert get_in(value, ["text", Access.at!(0)]) == "i"
      assert get_in(value, ["text", Access.at!(1)]) == "n"
      assert get_in(value, ["text", Access.at!(2)]) == "i"
      assert get_in(value, ["text", Access.at!(3)]) == "t"

      assert to_string(value["text"]) == "init"
    end

    test "should initialize text in Automerge.from()" do
      s1 = Automerge.from!(%{"text" => Automerge.text("init")})

      value = Automerge.get_document(s1)

      assert get_in(value, ["text", Access.at!(0)]) == "i"
      assert get_in(value, ["text", Access.at!(1)]) == "n"
      assert get_in(value, ["text", Access.at!(2)]) == "i"
      assert get_in(value, ["text", Access.at!(3)]) == "t"

      assert to_string(value["text"]) == "init"
    end

    test "should encode the initial value as a change" do
      s1 = Automerge.from!(%{"text" => Automerge.text("init")})
      changes = Automerge.get_all_changes(s1)

      assert Enum.count(changes) == 1
      s2 = Automerge.apply_changes(Automerge.init(), changes)

      value = Automerge.get_document(s2)

      assert is_struct(get_in(s2, ["text"]), Automerge.Text)
      assert List.to_string(value["text"]) == "init"
    end

    test "should allow immediate access to the value" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          text = Automerge.text("init")

          text = Text.delete_at(text, 3)
          assert to_string(text) == "ini"

          doc = put_in(doc, ["text"], text)

          assert to_string(doc["text"]) == "ini"

          doc
        end)

      value = Automerge.get_document(s1)

      assert to_string(value["text"]) == "ini"
    end

    test "should allow pre-assignment modification of the initial value" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          text = Automerge.text("init")

          text =
            text
            |> Text.delete_at(0)
            |> Text.insert_at(0, "I")

          put_in(doc["text"], text)
        end)

      value = Automerge.get_document(s1)

      assert List.to_string(value["text"]) == "Init"
    end
  end

  describe "non-textual control characters" do
    setup do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          text =
            Automerge.text()
            |> Text.insert_at(0, "a")
            |> Text.insert_at(1, %{"attribute" => "bold"})

          put_in(doc["text"], text)
        end)

      [s1: s1]
    end

    test "should allow fetching non-textual characters", %{s1: s1} do
      text = s1["text"]

      elem = get_in(text._elems, [1])

      assert Automerge.object_value(elem) == %{"attribute" => "bold"}
      assert elem.elem_id == "3@#{Automerge.get_actor_id(s1)}"
    end

    test "should include control characters in string length", %{s1: s1} do
      value = Automerge.get_document(s1)

      assert Enum.count(value["text"]) == 2
      assert get_in(value, ["text", Access.at(0)]) == "a"
    end

    test "should exclude control characters from toString()", %{s1: s1} do
      assert to_string(s1["text"]) == "a"
    end

    test "should allow control characters to be updated", %{s1: s1} do
      {s2, _} =
        Automerge.change!(s1, fn doc ->
          update_in(doc["text"][1], fn control ->
            Automerge.Map.put(control, "attribute", "italic")
          end)
        end)

      s3 = Automerge.load(Automerge.save(s2))

      text1 = s1["text"]
      elem1 = get_in(text1._elems, [1])

      assert Automerge.object_value(elem1) == %{"attribute" => "bold"}

      text2 = s2["text"]
      elem2 = get_in(text2._elems, [1])

      assert Automerge.object_value(elem2) == %{"attribute" => "italic"}

      text3 = s3["text"]
      elem3 = get_in(text3._elems, [1])

      assert Automerge.object_value(elem3) == %{"attribute" => "italic"}
    end
  end

  describe "spans interface to Text" do
    test "should return a simple string as a single span" do
      {s1, _patch} =
        Automerge.change!(
          Automerge.init(),
          &put_in(&1["text"], Automerge.text("hello world"))
        )

      assert Text.to_spans(s1["text"]) == ["hello world"]
    end

    test "should return an empty string as an empty array" do
      {s1, _patch} =
        Automerge.change!(
          Automerge.init(),
          &put_in(&1["text"], Automerge.text())
        )

      assert Text.to_spans(s1["text"]) == []
    end

    test "should split a span at a control character" do
      {s1, _patch} =
        Automerge.change!(
          Automerge.init(),
          &put_in(&1["text"], Automerge.text("hello world"))
        )

      {s1, _patch} =
        Automerge.change!(
          s1,
          &update_in(&1["text"], fn text ->
            Text.insert_at(text, 5, %{"attributes" => %{"bold" => true}})
          end)
        )

      assert Text.to_spans(s1["text"]) == [
               "hello",
               %{"attributes" => %{"bold" => true}},
               " world"
             ]
    end

    test "should allow consecutive control characters" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          doc = put_in(doc["text"], Automerge.text("hello world"))

          doc =
            update_in(doc["text"], &Text.insert_at(&1, 5, %{"attributes" => %{"bold" => true}}))

          doc =
            update_in(doc["text"], &Text.insert_at(&1, 6, %{"attributes" => %{"italic" => true}}))
        end)

      assert Text.to_spans(s1["text"]) == [
               "hello",
               %{"attributes" => %{"bold" => true}},
               %{"attributes" => %{"italic" => true}},
               " world"
             ]
    end

    test "should allow non-consecutive control characters" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          doc = put_in(doc["text"], Automerge.text("hello world"))

          doc =
            update_in(doc["text"], &Text.insert_at(&1, 5, %{"attributes" => %{"bold" => true}}))

          doc =
            update_in(
              doc["text"],
              &Text.insert_at(&1, 12, %{"attributes" => %{"italic" => true}})
            )
        end)

      assert Text.to_spans(s1["text"]) == [
               "hello",
               %{"attributes" => %{"bold" => true}},
               " world",
               %{"attributes" => %{"italic" => true}}
             ]
    end

    test "should be convertable into a Quill delta" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          doc
          |> put_in(["text"], Automerge.text("hello world"))
          |> update_in(["text"], &Text.insert_at(&1, 0, %{"attributes" => %{"bold" => true}}))
          |> update_in(["text"], &Text.insert_at(&1, 7 + 1, %{"attributes" => %{"bold" => nil}}))
          |> update_in(
            ["text"],
            &Text.insert_at(&1, 7 + 1, %{"attributes" => %{"color" => "#cccccc"}})
          )
        end)

      delta_doc = automerge_text_to_delta_doc(s1["text"])

      expected_doc = [
        %{"insert" => "Gandalf", "attributes" => %{"bold" => true}},
        %{"insert" => " the "},
        %{"insert" => "Grey", "attributes" => %{"bold" => "#cccccc"}}
      ]

      assert delta_doc == expected_doc
    end

    test "should support embeds" do
      {s1, _patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          doc
          |> put_in(["text"], Automerge.text("hello world"))
          |> update_in(
            ["text"],
            &Text.insert_at(&1, 0, %{"attributes" => %{"link" => "https://quilljs.com"}})
          )
          |> update_in(
            ["text"],
            &Text.insert_at(&1, 1, %{"image" => "https://quilljs.com/assets/images/icon.png"})
          )
          |> update_in(["text"], &Text.insert_at(&1, 2, %{"attributes" => %{"link" => nil}}))
        end)

      delta_doc = automerge_text_to_delta_doc(s1["text"])

      expected_doc = [
        %{
          "insert" => %{
            "image" => "https://quilljs.com/assets/images/icon.png"
          },
          "attributes" => %{
            "link" => "https://quilljs.com"
          }
        }
      ]

      assert delta_doc == expected_doc
    end

    test "should remain ordered" do
      {s1, patch} =
        Automerge.change!(Automerge.init(), fn doc ->
          put_in(doc["text"], Automerge.text("The quick brown fox jumps over the lazy dog"))
        end)

      assert Text.to_spans(s1["text"]) == ["The quick brown fox jumps over the lazy dog"]
    end

    test "should handle concurrent overlapping spans"

    test "should handle debolding spans"

    test "should handle destyling across destyled spans"

    test "should apply an insert"

    test "should apply an insert with control characters"

    test "should account for control characters in retain/delete lengths"
  end

  test "should support unicode when creating text" do
    s1 = Automerge.from!(%{"text" => Automerge.text("🐦")})

    assert to_string(s1["text"]) == "🐦"
  end
end
