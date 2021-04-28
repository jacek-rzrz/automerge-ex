defmodule Automerge.List do
  @moduledoc """
  # FIXME(ts): Add
  """
  @behaviour Access

  import Kernel, except: [length: 1]

  alias Automerge.Frontend.Context

  defstruct _object_id: nil,
            _conflicts: %{},
            _elem_ids: [],
            _max_elem: 0,
            _value: %{},
            _document: nil

  @impl Access
  def fetch(list, _key) do
    {:ok, list}
  end

  @impl Access
  def get_and_update(list, key, fun) do
    current = Map.get(list._value, key)

    current =
      if is_struct(current) do
        %{
          current
          | _document: %{
              list._document
              | _path: list._document._path ++ [%{object_id: current._object_id, key: key}]
            }
        }
      else
        current
      end

    case fun.(current) do
      {_prev, obj} when is_struct(obj) and not is_nil(obj._document) ->
        {obj, %{list | _document: obj._document}}

      {_prev, val} ->
        context = list._document._context
        path = list._document._path

        context =
          if is_nil(current) do
            Context.splice(context, path, key, 0, val)
          else
            Context.set_list_index(context, path, key, val)
          end

        {val, %{list | _document: %{list._document | _context: context}}}

      :pop ->
        pop(list, key)
    end
  end

  @impl Access
  def pop(list, key, _default \\ nil) do
    context = list._document._context
    path = list._document._path

    context = Context.splice(context, path, key, 1, [])

    val = Map.get(list._value, key)

    {val, %{list | _document: %{list._document | _context: context}}}
  end

  def first(list = %Automerge.List{}) do
    case Map.fetch(list._value, 0) do
      :error -> nil
      {:ok, value} -> value
    end
  end

  def last(list = %Automerge.List{}) do
    length = Enum.count(list) - 1

    case Map.fetch(list._value, length) do
      :error -> nil
      {:ok, value} -> value
    end
  end

  def insert_at(list = %Automerge.List{}, index, value) when is_number(index) do
    outside_document!(list)

    if index > length(list) or index < 0 do
      raise "Index, #{index}, is out of bounds for list"
    end

    if has_context?(list) do
      context = list._document._context
      path = list._document._path

      context = Context.splice(context, path, index, 0, List.wrap(value))
      updated_list = Context.get_object!(context, list._object_id)

      %{updated_list | _document: %{list._document | _context: context}}
    else
      %{list | _value: Map.put(list._value, index, value)}
    end
  end

  def delete_at(list = %Automerge.List{}, index, number_deleted \\ 1) when is_number(index) do
    outside_document!(list)

    if has_context?(list) do
      context = list._document._context
      path = list._document._path

      context = Context.splice(context, path, index, number_deleted, [])
      updated_list = Context.get_object!(context, list._object_id)

      %{updated_list | _document: %{list._document | _context: context}}
    else
      # Hmm splice?
      %{list | _value: MapSplice.splice(list._value, index, 1)}
    end
  end

  def replace_at(list = %Automerge.List{}, index, value) do
    outside_document!(list)

    if index > length(list) or index < 0 do
      raise "Index, #{index}, is out of bounds for list"
    end

    put_in(list, [index], value)
  end

  def update_at(list = %Automerge.List{}, index, callback) when is_function(callback, 1) do
    val = Map.fetch(list, index)
    resp = callback.(val)
    insert_at(list, index, resp)
  end

  def append(list = %Automerge.List{}, val) when is_list(val) do
    Enum.reduce(val, list, &append(&2, &1))
  end

  def append(list = %Automerge.List{}, val) do
    length = length(list)

    insert_at(list, length, val)
  end

  def prepend(list = %Automerge.List{}, val) do
    insert_at(list, 0, val)
  end

  def slice(list = %Automerge.List{}, first..last) do
    outside_document!(list)

    if has_context?(list) do
      context = list._document._context
      path = list._document._path

      context = Context.splice(context, path, first, last - first, [])
      updated_list = Context.get_object!(context, list._object_id)

      %{updated_list | _document: %{list._document | _context: context}}
    else
      %{list | _value: MapSplice.splice(list._value, first, last - first)}
    end
  end

  def splice(list = %Automerge.List{}, first, values) when is_list(values) do
    splice(list, first, 0, values)
  end

  def splice(list = %Automerge.List{}, first, delete_number) when is_number(delete_number) do
    splice(list, first, delete_number, %{})
  end

  def splice(list, first, delete_number, values) do
    outside_document!(list)

    if has_context?(list) do
      context = list._document._context
      path = list._document._path

      context = Context.splice(context, path, first, delete_number, values)

      %{list | _document: %{list._document | _context: context}}
    else
      %{list | _elems: MapSplice.splice(list._elems, first, delete_number, values)}
    end
  end

  def list(nil) do
    %Automerge.List{}
  end

  def list(initial) when is_list(initial) do
    append(%Automerge.List{}, initial)
  end

  def list(initial) do
    append(%Automerge.List{}, List.wrap(initial))
  end

  def length(list) do
    Enum.count(list._value)
  end

  defp has_context?(list) when not is_nil(list._document) and not is_nil(list._document._context),
    do: true

  defp has_context?(_list), do: false

  defp outside_document!(list) do
    if not is_nil(list._object_id) and is_nil(list._document) do
      raise "Cannot modify a list outside of a change callback"
    end
  end
end
