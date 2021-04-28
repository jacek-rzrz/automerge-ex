defmodule Automerge.Frontend.Context do
  @moduledoc false

  alias Automerge.Text

  alias Automerge.Frontend.{ApplyPatch, Context}

  defstruct actor_id: nil,
            max_op: nil,
            cache: %{},
            updated: %{},
            ops: [],
            apply_patch: &ApplyPatch.interpret_patch/3

  @type t() :: {
          actor_id :: String.t(),
          cache :: map(),
          updated :: map(),
          ops :: list(),
          diffs :: map()
        }

  @root_id "_root"

  defp get_path_object_id(path) do
    length = Enum.count(path) - 1

    Map.get(Enum.at(path, length), :object_id)
  end

  @spec add_op(Context.t(), map()) :: Context.t()
  def add_op(context, operation) do
    update_in(context.ops, &(&1 ++ List.wrap(operation)))
  end

  @spec next_op_id(Context.t()) :: String.t()
  def next_op_id(context) do
    "#{context.max_op + length(context.ops) + 1}@#{context.actor_id}"
  end

  def get_value_description!(context, value, is_list?) do
    case {value, is_list?} do
      {%DateTime{}, _} ->
        raise "Not implemented"

      {%_{_object_id: _}, _} ->
        object_id = value._object_id

        %{"objectId" => object_id, "type" => get_object_type(context, object_id)}

      {%_{elem_id: _, value: value}, true} ->
        %{"value" => value}

      {%_{}, _} ->
        raise "Unsupported type of value #{value}"

      {{_index, value}, true} ->
        %{"value" => value}

      {_, _} ->
        %{"value" => value}
    end
  end

  def get_values_descriptions!(context, path, object, key) do
    case object do
      %Text{} ->
        raise "Not implemented"

      obj when is_struct(obj, Automerge.Map) or is_struct(obj, Automerge.List) ->
        conflicts = get_in(object._conflicts, [key])

        unless conflicts do
          raise "No Children at key #{key} of path #{path}"
        end

        conflicts
        |> Map.keys()
        |> Enum.reduce(%{}, fn op_id, acc ->
          Map.put(
            acc,
            op_id,
            get_value_description!(context, conflicts[op_id], is_struct(obj, Automerge.List))
          )
        end)
    end
  end

  def get_property_value(object, key, op_id) do
    case object do
      %Text{} ->
        raise "not implemented"

      %_{} ->
        get_in(object._conflicts, [key, op_id])
    end
  end

  def apply_at_path(context, path, callback) do
    patch = %{"objectId" => "_root", "type" => "map", "props" => %{}}

    {patch, subpatch, patch_path} = get_subpatch(context, patch, path)

    {context, subpatch} = callback.(subpatch)

    patch =
      if path == [] do
        subpatch
      else
        apply_subpatch_at_path(patch, subpatch, patch_path)
      end

    context.apply_patch.(context, patch, get_in(context.cache, [@root_id]))
  end

  defp next_subpatch_path_op(values, path_elem) do
    Enum.reduce(Map.keys(values), fn op_id, acc ->
      if get_in(values, [op_id, "objectId"]) === path_elem.object_id do
        op_id
      else
        acc
      end
    end)
  end

  defp apply_subpatch_at_path(patch, subpatch, patch_path) do
    update_in(
      patch,
      Enum.reduce(patch_path, [], fn {key, next}, acc ->
        acc ++ [Access.key("props", %{}), Access.key(key, %{}), Access.key(next, %{})]
      end),
      fn _sub ->
        subpatch
      end
    )
  end

  def get_subpatch(context, patch, path) do
    object = get_object!(context, @root_id)

    {patch, subpatch, patch_path, _object} =
      for path_elem <- path, reduce: {patch, patch, [], object} do
        {_patch, subpatch, path_path, object} ->
          # Ensure props exist
          subpatch = Map.merge(%{"props" => %{}}, subpatch)

          # Add the path_elem.key to our subpatch if it doesn't exist currently
          subpatch =
            if is_nil(get_in(subpatch, ["props", path_elem.key])) do
              put_in(
                subpatch,
                ["props", path_elem.key],
                get_values_descriptions!(context, path, object, path_elem.key)
              )
            else
              subpatch
            end

          # Get the values of our subpatch path_elm
          values = get_in(subpatch, ["props", path_elem.key])

          next_op_id = next_subpatch_path_op(values, path_elem)

          unless next_op_id do
            raise "Cannot find path object with objectId #{path_elem.object_id}"
          end

          patch = subpatch
          subpatch = get_in(values, [next_op_id])

          {
            patch,
            subpatch,
            path_path ++ [{path_elem.key, next_op_id}],
            get_property_value(object, path_elem.key, next_op_id)
          }
      end

    subpatch = Map.merge(%{"props" => %{}}, subpatch)

    {patch, subpatch, patch_path}
  end

  def get_object!(context, object_id) do
    object = Map.get(context.updated, object_id) || Map.get(context.cache, object_id)

    unless object do
      raise "Target object does not exist: #{object_id}"
    end

    object
  end

  def get_object_type(_context, object_id) when object_id == @root_id, do: "map"

  def get_object_type(context, object_id) do
    case get_object!(context, object_id) do
      %Text{} -> "text"
      %Automerge.List{} -> "list"
      _ -> "map"
    end
  end

  def get_object_field(_context, _path, _object_id, key) when is_atom(key),
    do: raise("atoms not supported for object field keys")

  def get_object_field(context, _path, object_id, key) do
    object = get_object!(context, object_id)

    case object do
      %Automerge.Map{} -> Map.get(object._value, key)
      %Automerge.List{} -> Map.get(object._value, key)
      %Text{} -> Map.get(object._elems, key)
    end
  end

  defp existing_object!(%_{_object: id}) when not is_nil(id) do
    raise "Cannot create a reference to an existing document object"
  end

  defp existing_object!(value), do: value

  def create_nested_objects!(context, obj, key, value, insert, pred, elem_id \\ nil) do
    existing_object!(value)

    object_id = next_op_id(context)

    case value do
      %Automerge.Text{} ->
        context =
          add_op(
            context,
            if is_nil(elem_id) do
              %{
                "action" => "makeText",
                "obj" => obj,
                "key" => key,
                "insert" => insert,
                "pred" => pred
              }
            else
              %{
                "action" => "makeText",
                "obj" => obj,
                "elemId" => elem_id,
                "insert" => insert,
                "pred" => pred
              }
            end
          )

        subpatch = %{"objectId" => object_id, "type" => "text", "edits" => [], "props" => %{}}
        insert_list_items!(context, subpatch, 0, value, true, :text)

      %Automerge.List{} ->
        context =
          add_op(
            context,
            if is_nil(elem_id) do
              %{
                "action" => "makeList",
                "obj" => obj,
                "key" => key,
                "insert" => insert,
                "pred" => pred
              }
            else
              %{
                "action" => "makeList",
                "obj" => obj,
                "elemId" => elem_id,
                "insert" => insert,
                "pred" => pred
              }
            end
          )

        subpatch = %{"objectId" => object_id, "type" => "list", "edits" => [], "props" => %{}}
        insert_list_items!(context, subpatch, 0, value, true)

      _ ->
        context =
          add_op(
            context,
            if is_nil(elem_id) do
              %{
                "action" => "makeMap",
                "obj" => obj,
                "key" => key,
                "insert" => insert,
                "pred" => pred
              }
            else
              %{
                "action" => "makeMap",
                "obj" => obj,
                "elemId" => elem_id,
                "insert" => insert,
                "pred" => pred
              }
            end
          )

        value =
          if is_struct(value, Text.Elem) do
            value.value
          else
            value
          end

        {context, props} =
          value
          |> Map.keys()
          |> Enum.sort()
          |> Enum.reduce({context, %{}}, fn nested, {context, props} ->
            op_id = next_op_id(context)

            {context, value_patch} =
              set_value!(context, object_id, nested, get_in(value, [nested]), false, [])

            {context, Map.put(props, nested, %{"#{op_id}" => value_patch})}
          end)

        {context, %{"objectId" => object_id, "type" => "map", "props" => props}}
    end
  end

  defp valid_type!(value) do
    cond do
      is_map(value) ->
        true

      is_list(value) ->
        true

      is_binary(value) ->
        true

      is_number(value) ->
        true

      is_boolean(value) ->
        true

      is_nil(value) ->
        true

      is_tuple(value) and tuple_size(value) == 2 ->
        case value do
          {key, value} when is_number(key) ->
            valid_type!(value)

          _ ->
            raise "Unsupported type of value: #{inspect(value)}"
        end

      true ->
        raise "Unsupported type of value: #{inspect(value)}"
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def set_value!(context, object_id, key, value, insert, pred, elem_id \\ nil) do
    # Check our values type
    valid_type!(value)

    unless object_id do
      raise "setValue needs an objectId"
    end

    unless key !== "" do
      raise "The key of a map entry must not be an empty string"
    end

    case value do
      ## Create objects when they are properties of maps

      value when is_struct(value, Automerge.List) and value._object_id === nil ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      value when is_struct(value, Automerge.Text) and value._object_id === nil ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      value
      when is_struct(value, Automerge.Text.Elem) and value.value !== nil and
             not is_binary(value.value) ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)


      value when is_map(value) and not is_struct(value) ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      ## Create objects when they are properties of lists/text

      {_index, value} when is_struct(value, Automerge.List) and value._object_id === nil ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      {_index, value} when is_struct(value, Automerge.Text) and value._object_id === nil ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      {_index, value}
      when is_struct(value, Automerge.Text.Elem) and value.value === nil and
             not is_binary(value.value) ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      ## Support Bare types

      {_index, value} when is_map(value) and not is_struct(value) ->
        create_nested_objects!(context, object_id, key, value, insert, pred, elem_id)

      _ ->
        description = get_value_description!(context, value, is_number(key))

        op =
          if is_nil(elem_id) do
            %{
              "action" => "set",
              "obj" => object_id,
              "key" => key,
              "insert" => insert,
              "pred" => pred
            }
          else
            %{
              "action" => "set",
              "obj" => object_id,
              "elemId" => elem_id,
              "insert" => insert,
              "pred" => pred
            }
          end

        context = add_op(context, Map.merge(op, description))

        {context, description}
    end
  end

  def set_map_key!(context, path, key, value) when is_binary(key) do
    object_id =
      if path === [] do
        @root_id
      else
        get_path_object_id(path)
      end

    object = get_object!(context, object_id)

    existing_value = Map.get(object._value, key, nil)
    conflicts = Map.get(object._conflicts, key, %{})

    if value !== existing_value or Enum.count(conflicts) > 1 or is_nil(value) do
      apply_at_path(context, path, fn subpatch ->
        pred = get_pred(object, key)
        op_id = next_op_id(context)

        {context, value_patch} = set_value!(context, object_id, key, value, false, pred)

        subpatch = put_in(subpatch, ["props", key], %{"#{op_id}" => value_patch})

        {context, subpatch}
      end)
    else
      context
    end
  end

  def set_map_key!(_context, _path, key, _value),
    do: raise("The key of the map entry must be a string, got #{key}")

  def delete_map_key(context, path, key) do
    object_id =
      if path === [] do
        @root_id
      else
        get_path_object_id(path)
      end

    object = get_object!(context, object_id)

    if Map.has_key?(object._value, key) do
      pred = get_pred(object, key)

      context =
        add_op(context, %{
          "action" => "del",
          "obj" => object_id,
          "key" => key,
          "insert" => false,
          "pred" => pred
        })

      apply_at_path(context, path, fn subpatch ->
        subpatch = put_in(subpatch, ["props", key], %{})

        {context, subpatch}
      end)
    else
      context
    end
  end

  def insert_list_items!(context, subpatch, index, values, new_object, subtype \\ :list) do
    # If were creating a new object, we need to know which kind.
    list =
      if new_object do
        case subtype do
          :list -> %Automerge.List{}
          :text -> %Text{}
        end
      else
        get_object!(context, Map.get(subpatch, "objectId"))
      end

    elements =
      if is_struct(list, Automerge.List) do
        Enum.count(list._value)
      else
        Enum.count(list)
      end

    if index < 0 || index > elements do
      raise "List index #{index} is out of bounds for list of length #{elements}"
    end

    elem_id = get_elem_id!(list, index, true)

    values =
      case values do
        %Text{} ->
          values._elems

        %Automerge.List{} ->
          values._value

        values when is_list(values) ->
          values
          |> Enum.with_index()
          |> Enum.map(fn {value, key} -> {key, value} end)
          |> Enum.into(%{})

        values when is_map(values) ->
          values
      end

    length = map_size(values)

    range_end =
      if length > 0 do
        length - 1
      else
        0
      end

    {context, subpatch, _elem_id} =
      if length > 0 do
        for offset <- 0..range_end, reduce: {context, subpatch, elem_id} do
          {context, subpatch, elem_id} ->
            next_op_id = next_op_id(context)

            value = Map.get(values, offset)

            {context, value_patch} =
              set_value!(
                context,
                Map.get(subpatch, "objectId"),
                index + offset,
                value,
                true,
                [],
                elem_id
              )

            elem_id = next_op_id

            subpatch =
              update_in(subpatch, ["edits"], fn edits ->
                edits ++ [%{"action" => "insert", "index" => index + offset, "elemId" => elem_id}]
              end)

            subpatch = put_in(subpatch, ["props", index + offset], %{"#{elem_id}" => value_patch})

            {context, subpatch, elem_id}
        end
      else
        {context, subpatch, elem_id}
      end

    {context, subpatch}
  end

  def set_list_index(context, path, index, value) when is_number(index) do
    object_id =
      if path === [] do
        @root_id
      else
        get_path_object_id(path)
      end

    list = get_object!(context, object_id)

    elements =
      if is_struct(list, Automerge.List) do
        Enum.count(list._value)
      else
        Enum.count(list)
      end

    if index < 0 || index > elements do
      raise "List index #{index} is out of bounds for the list of length #{elements}"
    end

    if index === elements do
      splice(context, path, index, 0, [value])
    else
      existing_value =
        if is_struct(list, Automerge.List) do
          Enum.at(list._value, index, nil)
        else
          Enum.at(list._elems, index, nil)
        end

      conflicts =
        if is_struct(Automerge.List) do
          Enum.at(list._value, index, nil)
        else
          %{}
        end

      if value !== existing_value or Enum.count(conflicts) > 1 or is_nil(value) do
        apply_at_path(context, path, fn subpatch ->
          pred = get_pred(list, index)
          op_id = next_op_id(context)

          {context, value_patch} =
            set_value!(context, object_id, index, value, false, pred, get_elem_id!(list, index))

          subpatch = put_in(subpatch, ["props", index], %{"#{op_id}" => value_patch})

          {context, subpatch}
        end)
      else
        context
      end
    end
  end

  def splice(context, path, start, deletions, insertions) do
    object_id =
      if path === [] do
        @root_id
      else
        get_path_object_id(path)
      end

    list = get_object!(context, object_id)

    elements =
      if is_struct(list, Automerge.List) do
        Enum.count(list._value)
      else
        Enum.count(list)
      end

    if start < 0 || deletions < 0 || start > elements - deletions do
      raise "#{deletions} deletions starting at index #{start} are out of bounds for list of length #{elements}"
    end

    {patch, subpatch, patch_path} = get_subpatch(context, %{}, path)

    subpatch = Map.merge(%{"edits" => []}, subpatch)

    {context, patch, subpatch} =
      if deletions == 0 && Enum.empty?(insertions) do
        {context, patch, subpatch}
      else
        if deletions > 0 do
          range_end = deletions - 1

          {context, patch, subpatch} =
            for index <- 0..range_end, reduce: {context, patch, subpatch} do
              {context, patch, subpatch} ->
                elem_id = get_elem_id!(list, start + index)
                pred = get_pred(list, start + index)

                context =
                  add_op(context, %{
                    "action" => "del",
                    "obj" => object_id,
                    "elemId" => elem_id,
                    "insert" => false,
                    "pred" => pred
                  })

                subpatch =
                  update_in(subpatch["edits"], fn edits ->
                    edits ++ [%{"action" => "remove", "index" => start}]
                  end)

                {context, patch, subpatch}
            end

          {context, patch, subpatch}
        else
          {context, patch, subpatch}
        end
      end

    {context, subpatch} =
      if Enum.count(insertions) > 0 do
        insert_list_items!(
          context,
          subpatch,
          start,
          insertions,
          false
        )
      else
        {context, subpatch}
      end

    patch =
      apply_subpatch_at_path(
        patch,
        subpatch,
        patch_path
      )

    patch = Map.merge(patch, %{"objectId" => "_root", "type" => "map"})

    context.apply_patch.(context, patch, get_in(context.cache, [@root_id]))
  end

  defp get_pred(object, key) do
    case object do
      %Text{} ->
        elem = get_in(object._elems, [key])

        elem.pred

      %_{_conflicts: _} ->
        case get_in(object._conflicts, [key]) do
          nil -> []
          conflicts -> Map.keys(conflicts)
        end

      _ ->
        []
    end
  end

  def get_elem_id!(list, index, insert \\ false) do
    index =
      if insert do
        index - 1
      else
        index
      end

    cond do
      insert && index === -1 ->
        "_head"

      is_struct(list, Automerge.List) and !is_nil(list._elem_ids) ->
        get_in(
          list._elem_ids,
          [Access.at(index)]
        )

      is_struct(list, Text) and !is_nil(get_in(list._elems, [index])) ->
        elem = get_in(list._elems, [index])

        elem.elem_id

      true ->
        raise "Cannot find elemId at list index"
    end
  end
end
