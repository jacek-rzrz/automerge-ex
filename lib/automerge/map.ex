defmodule Automerge.Map do
  @moduledoc false
  @behaviour Access

  alias Automerge.Frontend.Context

  defstruct _object_id: nil, _conflicts: %{}, _value: %{}, _document: nil

  @type t() :: {
          _object_id :: String.t(),
          _conflicts :: map(),
          _change :: any(),
          _value :: map()
        }

  @impl Access
  @doc false
  def fetch(map, key) do
    sub_value = Map.get(map._value, key)

    result =
      if is_struct(sub_value) do
        sub_value
      else
        map
      end

    {:ok, result}
  end

  @impl Access
  @doc false
  def get_and_update(map, key, fun) do
    current = Map.get(map._value, key)

    current =
      if is_struct(current) do
        %{
          current
          | _document: %{
              map._document
              | _path: map._document._path ++ [%{object_id: current._object_id, key: key}]
            }
        }
      else
        current
      end

    case fun.(current) do
      {_prev, obj} when is_struct(obj) and not is_nil(obj._document) ->
        {obj, %{map | _document: obj._document}}

      {_prev, val} ->
        context = map._document._context
        path = map._document._path

        context = Context.set_map_key!(context, path, key, val)

        {val, %{map | _document: %{map._document | _context: context}}}

      :pop ->
        pop(map, key)
    end
  end

  @impl Access
  @doc false
  def pop(map, key, _default \\ nil) do
    context = map._document._context
    path = map._document._path

    context = Context.delete_map_key(context, path, key)

    val = Map.get(map._value, key)

    {val, %{map | _document: %{map._document | _context: context}}}
  end

  def put(map = %Automerge.Map{}, key, value) when is_binary(key) do
    outside_document!(map)

    if has_context?(map) do
      context = map._document._context
      path = map._document._path

      context = Context.set_map_key!(context, path, key, value)

      %{map | _document: %{map._document | _context: context}}
    else
      %{map | _value: Map.put(map._value, key, value)}
    end
  end

  def put(_map, key, _value) when is_number(key),
    do: raise("Numeric keys are unsupported as keys: #{key}")

  def merge(m1, m2) when is_struct(m1, Automerge.Map) do
    outside_document!(m1)

    if has_context?(m1) do
      context = m1._document._context
      path = m1._document._path

      context =
        Enum.reduce(m2, context, fn {key, value}, acc ->
          Context.set_map_key!(acc, path, key, value)
        end)

      %{context | _document: %{m1._document | _context: context}}
    else
      %{m1 | _value: Map.merge(m1._value, m2)}
    end
  end

  def delete(map = %Automerge.Map{}, key) do
    outside_document!(map)

    if has_context?(map) do
      context = map._document._context
      path = map._document._path

      context = Context.delete_map_key(context, path, key)

      %{map | _document: %{map._document | _context: context}}
    else
      %{map | _value: Map.delete(map._value, key)}
    end
  end

  defp has_context?(map) when not is_nil(map._document) and not is_nil(map._document._context),
    do: true

  defp has_context?(_map), do: false

  defp outside_document!(map) do
    if not is_nil(map._object_id) and is_nil(map._document) do
      raise "Cannot modify a list outside of a change callback"
    end
  end
end
