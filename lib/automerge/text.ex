defmodule Automerge.Text do
  @moduledoc """
  # FIXME(ts): Add
  """
  @behaviour Access

  alias Automerge.Frontend.Context

  alias Automerge.Text

  defstruct _object_id: nil, _elems: %{}, _path: nil, _document: nil

  import Kernel, except: [length: 1]

  @impl Access
  def fetch(text, _key) do
    {:ok, text}
  end

  @impl Access
  def get_and_update(text, key, fun) do
    current = Map.get(text._elems, key)

    {_list, val} = fun.(current)

    context = text._document._context
    path = text._document._path

    context =
      if is_nil(current) do
        Context.splice(context, path, key, 0, val)
      else
        Context.set_list_index(context, path, key, val)
      end

    {val, %{text | _document: %{text._document | _context: context}}}
  end

  @impl Access
  def pop(text, key, _default \\ nil) do
    context = text._document._context
    path = text._document._path

    context = Context.splice(context, path, key, 1, [])

    val = Map.get(text._value, key)

    {val, %{text | _document: %{text._document | _context: context}}}
  end

  defmodule Elem do
    @moduledoc false
    @behaviour Access

    defstruct [:value, :index, :elem_id, :pred]

    @impl Access
    def fetch(elem, _key) do
      {:ok, elem}
    end

    @impl Access
    def get_and_update(elem, _key, fun) do
      {_prev, val} = fun.(elem.value)

      {val, %{elem | value: val}}
    end

    @impl Access
    def pop(_elem, _key, _default \\ nil) do
      raise "fixme implment"
    end
  end

  def insert_at(text = %Automerge.Text{}, index, values) do
    outside_document!(text)

    if has_context?(text) do
      values =
        if is_list(values) do
          Enum.map(values, fn value -> %Text.Elem{value: value} end)
        else
          %Text.Elem{value: values}
        end

      context = text._document._context
      path = text._document._path

      context = Context.splice(context, path, index, 0, List.wrap(values))
      updated_text = Context.get_object!(context, text._object_id)

      %{updated_text | _document: %{text._document | _context: context}}
    else
      values =
        values
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.map(fn {value, key} -> {key, value} end)

      %{text | _elems: MapSplice.splice(text._elems, index, values)}
    end
  end

  def delete_at(text = %Automerge.Text{}, index, number_deleted \\ 1) do
    outside_document!(text)

    if has_context?(text) do
      context = text._document._context
      path = text._document._path

      context = Context.splice(context, path, index, number_deleted, [])
      updated_text = Context.get_object!(context, text._object_id)

      %{updated_text | _document: %{text._document | _context: context}}
    else
      %{text | _elems: MapSplice.splice(text._elems, index, number_deleted)}
    end
  end

  def get_elem_id!(text, index) do
    case get_in(text._elems, [index]) do
      nil -> raise "Cannot find elemId at list index"
      elem -> elem.elem_id
    end
  end

  def text(nil) do
    %Text{}
  end

  def text(text) when is_list(text) do
    elems =
      text
      |> Enum.map(&%Elem{value: &1})
      |> Enum.with_index()
      |> Enum.map(fn {value, key} -> {key, value} end)
      |> Enum.into(%{})

    %Text{_elems: elems}
  end

  def text(text) when is_binary(text) do
    elems =
      text
      |> String.graphemes()
      |> Enum.map(&%Elem{value: &1})
      |> Enum.with_index()
      |> Enum.map(fn {value, key} -> {key, value} end)
      |> Enum.into(%{})

    %Text{_elems: elems}
  end

  def length(text) do
    Enum.count(text._elems)
  end

  def to_spans(%_{_elems: elems}) when map_size(elems) == 0, do: []

  def to_spans(text = %Automerge.Text{}) do
    {spans, elem} =
      for index <- 0..(Enum.count(text._elems) - 1), reduce: {[], ""} do
        {spans, acc} ->
          elem = Map.get(text._elems, index)

          if is_struct(elem.value) do
            spans =
              if String.length(acc) > 0 do
                spans ++ List.wrap(acc)
              else
                spans
              end

            {spans ++ [Automerge.object_value(elem)], ""}
          else
            {spans, acc <> elem.value}
          end
      end

    if String.length(elem) > 0 do
      spans ++ List.wrap(elem)
    else
      spans
    end
  end

  defp has_context?(text) when not is_nil(text._document) and not is_nil(text._document._context),
    do: true

  defp has_context?(_text), do: false

  defp outside_document!(text) do
    if not is_nil(text._object_id) and is_nil(text._document) do
      raise "Cannot modify a list outside of a change callback"
    end
  end
end
