defmodule Automerge.Frontend.ApplyPatch do
  @moduledoc false

  alias Automerge.Text

  alias Automerge.Frontend.{Context}

  defp parse_op_id!(op_id) do
    case Regex.scan(~r{/^(\d+)@(.*)$/}, op_id) do
      [_, counter, actor_id] ->
        %{counter: String.to_integer(counter), actor_id: actor_id}

      _ ->
        raise "Not a valid opId: #{op_id}"
    end
  end

  defp get_value(context, patch, object) do
    cond do
      patch["objectId"] ->
        # Replace the object with a new one
        if is_struct(object) && object._object_id !== patch["objectId"] do
          interpret_patch(context, patch, nil)
        else
          interpret_patch(context, patch, object)
        end

      patch["datatype"] === "timestamp" ->
        DateTime.from_unix!(patch["value"])

      true ->
        patch["value"]
    end
  end

  defp lamport_compare(ts1, ts2) do
    time1 =
      if Regex.match?(~r{/^(\d+)@(.*)$/}, ts1) do
        parse_op_id!(ts1)
      else
        %{counter: 0, actor_id: ts1}
      end

    time2 =
      if Regex.match?(~r{/^(\d+)@(.*)$/}, ts2) do
        parse_op_id!(ts2)
      else
        %{counter: 0, actor_id: ts2}
      end

    cond do
      time1.counter < time2.counter -> true
      time1.counter > time2.counter -> false
      time1.actor_id < time2.actor_id -> true
      time1.actor_id > time2.actor_id -> false
    end
  end

  defp apply_properties(context, nil, object), do: {context, object}

  defp apply_properties(context, props, object) do
    props
    |> Map.keys()
    |> Enum.reduce({context, object}, fn key, {context, object} ->
      op_ids =
        props
        |> Map.get(key)
        |> Map.keys()
        |> Enum.sort(&lamport_compare/2)
        |> Enum.reverse()

      {context, values} =
        Enum.reduce(op_ids, {context, %{}}, fn op_id, {context, values} ->
          subpatch = get_in(props, [key, op_id])

          conflict_value =
            case get_in(object._conflicts, [key, op_id]) do
              nil -> nil
              resp -> resp
            end

          case get_value(context, subpatch, conflict_value) do
            context = %Context{} ->
              {context, Map.put(values, op_id, Map.get(context.updated, subpatch["objectId"]))}

            value ->
              {context, Map.put(values, op_id, value)}
          end
        end)

      key =
        if is_struct(object, Automerge.List) and not is_number(key) do
          String.to_integer(key)
        else
          key
        end

      if op_ids === [] do
        {
          context,
          %{
            object
            | _value: Map.delete(object._value, key),
              _conflicts: Map.delete(object._conflicts, key)
          }
        }
      else
        {
          context,
          %{
            object
            | _value: Map.put(object._value, key, values[hd(op_ids)]),
              _conflicts: Map.put(object._conflicts, key, values)
          }
        }
      end
    end)
  end

  defp iterate_edits(edits, list, _callbacks) when is_nil(edits), do: list

  defp iterate_edits(edits, list,
         insert_callback: insert_callback,
         remove_callback: remove_callback
       ) do
    {_el, list} =
      Enum.reduce(
        edits,
        {%{splice_pos: -1, deletions: 0, insertions: []}, list},
        fn edit, {el, list} ->
          %{"action" => action, "index" => index, "elemId" => elem_id} =
            Map.merge(%{"elemId" => nil}, edit)

          el =
            if el.splice_pos < 0 do
              %{el | splice_pos: index, deletions: 0, insertions: []}
            else
              el
            end

          case action do
            "insert" ->
              el = %{el | insertions: el.insertions ++ [elem_id]}

              if index == Enum.count(edits) - 1 ||
                   get_in(edits, [Access.at(index + 1), "action"]) !== "insert" ||
                   get_in(edits, [Access.at(index + 1), "index"]) !== index + 1 do
                list = insert_callback.({el.splice_pos, el.insertions})

                {%{el | splice_pos: -1}, list}
              else
                {el, list}
              end

            "remove" ->
              el = %{el | deletions: el.deletions + 1}

              if index == Enum.count(edits) - 1 ||
                   get_in(edits, [Access.at(index + 1), "action"]) !== "remove" ||
                   get_in(edits, [Access.at(index + 1), "index"]) !== index + 1 do
                list = remove_callback.({el.splice_pos, el.deletions})

                {%{el | splice_pos: -1}, list}
              else
                {el, list}
              end

            _ ->
              raise "Unknown list edit action #{action}"
          end
        end
      )

    list
  end

  defp update_map_object(context, patch, obj) do
    object_id = patch["objectId"]

    updated =
      if Map.get(context.updated, object_id) do
        context.updated
      else
        Map.put(
          context.updated,
          object_id,
          Map.get(context.cache, object_id, %Automerge.Map{
            _object_id: object_id,
            _conflicts:
              if is_struct(obj, Object) do
                obj._conflicts
              else
                %{}
              end
          })
        )
      end

    object = Map.get(updated, object_id)

    {context, object} = apply_properties(context, patch["props"], object)

    # Make sure the object gets put in updated.
    updated = put_in(context.updated, [object_id], object)

    %{context | updated: updated}
  end

  defp update_table_object(_context, _patch, _obj) do
  end

  defp update_list_object(context, patch, _obj) do
    object_id = patch["objectId"]

    updated =
      if Map.get(context.updated, object_id) do
        context.updated
      else
        Map.put(
          context.updated,
          object_id,
          Map.get(context.cache, object_id, %Automerge.List{_object_id: object_id})
        )
      end

    list = Map.get(updated, object_id)

    list =
      iterate_edits(
        patch["edits"],
        list,
        insert_callback: fn {index, new_elems} ->
          blanks =
            Enum.map(0..(Enum.count(new_elems) - 1), fn _index -> nil end)
            |> Enum.with_index()
            |> Enum.map(fn {v, k} -> {k, v} end)
            |> Enum.into(%{})

          %{
            list
            | _elem_ids: splice(list._elem_ids, index, 0, new_elems),
              _value: splice(list._value, index, 0, blanks),
              _conflicts: splice(list._conflicts, index, 0, blanks)
          }
        end,
        remove_callback: fn {index, count} ->
          %{
            list
            | _elem_ids: splice(list._elem_ids, index, count),
              _value: splice(list._value, index, count),
              _conflicts: splice(list._conflicts, index, count)
          }
        end
      )

    {context, list} = apply_properties(context, patch["props"], list)

    updated = put_in(context.updated, [object_id], list)

    %{context | updated: updated}
  end

  defp update_text_object(context, patch, obj) do
    object_id = patch["objectId"]

    updated_obj = Map.get(context.updated, object_id)
    cache_obj = Map.get(context.cache, object_id)

    elems =
      cond do
        not is_nil(updated_obj) -> updated_obj._elems
        is_struct(obj, Automerge.Text) -> obj._elems
        not is_nil(cache_obj) -> cache_obj._elems
        true -> %{}
      end

    elems =
      iterate_edits(
        patch["edits"],
        elems,
        insert_callback: fn {index, elem_ids} ->
          blanks =
            elem_ids
            |> Enum.with_index()
            |> Enum.map(fn {v, k} -> {k, %{"elemId" => v}} end)
            |> Enum.into(%{})

          splice(elems, index, 0, blanks)
        end,
        remove_callback: fn {index, deletions} ->
          splice(elems, index, deletions)
        end
      )

    prop_indexes =
      if patch["props"] do
        Map.keys(patch["props"])
      else
        []
      end

    elems =
      for index <- prop_indexes, reduce: elems do
        elems ->
          elem_index =
            if is_number(index) do
              index
            else
              String.to_integer(index)
            end

          pred = Map.keys(get_in(patch, ["props", index]))
          op_id = pred |> Enum.sort(&lamport_compare/2) |> Enum.reverse() |> hd()

          unless op_id do
            raise "No default value at index #{elem_index}"
          end

          value_or_context =
            get_value(
              context,
              get_in(patch, ["props", index, op_id]),
              get_in(elems, ["key", "value"])
            )

          base =
            case get_in(elems, [elem_index, "elemId"]) do
              elem when is_struct(elem, Text.Elem) -> elem
              elem_id -> %Text.Elem{elem_id: elem_id}
            end

          put_in(
            elems[elem_index],
            %{
              base
              | pred: pred,
                value:
                  case value_or_context do
                    %Context{} ->
                      Context.get_object!(value_or_context, op_id)

                    _ ->
                      value_or_context
                  end
            }
          )
      end

    updated = put_in(context.updated, [object_id], %Text{_object_id: object_id, _elems: elems})

    %{context | updated: updated}
  end

  def interpret_patch(context, patch, obj) do
    if is_map(obj) &&
         !Map.get(patch, "props") && !Map.get(patch, "edits") &&
         !Map.get(context.updated, patch["objectId"]) do
      %{context | updated: Map.put(context.updated, patch["objectId"], obj)}
    else
      case patch["type"] do
        "map" -> update_map_object(context, patch, obj)
        "table" -> update_table_object(context, patch, obj)
        "list" -> update_list_object(context, patch, obj)
        "text" -> update_text_object(context, patch, obj)
        _ -> raise "Unknown object type #{patch["type"]}"
      end
    end
  end

  defp splice(list, start, value) when is_list(value) do
    splice(list, start, 0, value)
  end

  defp splice(list, start, delete_count) when is_number(delete_count) do
    splice(list, start, delete_count, [])
  end

  defp splice(list, start, delete_count, value) when is_map(list) do
    start_range = 0..(start - 1)
    beginning = start + delete_count
    stop = beginning..Enum.count(list)

    enum =
      list
      |> Enum.sort_by(fn {key, _val} -> key end)
      |> Enum.map(fn {_key, value} -> value end)

    if start > 0 do
      Enum.slice(enum, start_range)
    else
      []
    end
    |> Kernel.++(Enum.map(value, fn {_key, value} -> value end))
    |> Kernel.++(Enum.slice(enum, stop))
    |> Enum.with_index()
    |> Enum.map(fn {value, key} -> {key, value} end)
    |> Enum.into(%{})
  end

  defp splice(list, start, delete_count, value) when is_list(list) do
    start_range = 0..(start - 1)
    beginning = start + delete_count
    stop = beginning..-1

    list
    |> Enum.slice(start_range)
    |> Kernel.++(value)
    |> Kernel.++(Enum.slice(list, stop))
  end
end
