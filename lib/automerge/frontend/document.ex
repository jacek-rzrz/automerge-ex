defmodule Automerge.Frontend.Document do
  @moduledoc false
  @behaviour Access

  defstruct _object_id: nil, _context: nil, _path: []

  alias Automerge.Frontend.{Context, Document}

  @root_id "_root"

  def object_proxy(am, actor_id, object_id \\ @root_id) do
    context = %Context{
      actor_id: actor_id,
      max_op: am._state.max_op,
      cache: am._cache
    }

    %Document{
      _object_id: object_id,
      _context: context
    }
  end

  @impl Access
  def fetch(doc = %Document{_object_id: object_id, _context: context, _path: path}, key) do
    doc_object = Context.get_object!(context, object_id)

    # TODO(ts): Handle lists, etc...
    case {path, get_in(doc_object._value, [key])} do
      # If were at the root object, were a map.
      {[], nil} ->
        {:ok, %{}}

      {_, nil} ->
        :error

      {_, value} when is_struct(value, Automerge.Map) or is_struct(value, Automerge.List) ->
        {:ok, %{doc | _object_id: value._object_id, _path: path ++ List.wrap(key)}}

      {_, value} ->
        {:ok, value}
    end
  end

  @impl Access
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def get_and_update(
        doc = %Document{_object_id: object_id, _context: context, _path: path},
        key,
        fun
      ) do
    doc_object = Context.get_object!(context, object_id)
    is_root? = object_id === "_root"
    is_list_doc? = is_struct(doc_object, Automerge.List) or is_struct(doc_object, Automerge.Text)

    fetch =
      if is_map_key(doc_object, :_value) do
        Map.fetch(doc_object._value, key)
      else
        :error
      end

    {object, value} =
      case {is_root?, fetch, is_list_doc?} do
        {false, :error, false} ->
          raise "Currently unsupported"

        # Potentially a new object
        {false, :error, true} ->
          {doc_object,
           %{
             doc_object
             | _document: %{doc | _path: path ++ [%{object_id: doc_object._object_id, key: key}]}
           }}

        {true, :error, _} ->
          update =
            if is_number(key) do
              []
            else
              %{}
            end

          context = Context.set_map_key!(context, path, key, update)

          new_doc = %Document{_object_id: "_root", _context: context, _path: []}

          object_id = Automerge.get_object_id(get_in(new_doc, Enum.map(path, & &1.key) ++ [key]))

          {
            new_doc,
            %{
              doc_object
              | _document: %Document{
                  _object_id: object_id,
                  _context: context,
                  _path: path ++ [%{object_id: object_id, key: key}]
                }
            }
          }

        {true, {:ok, value}, _} when is_struct(value, Text) ->
          {value,
           %{value | _context: context, _path: path ++ [%{object_id: value._object_id, key: key}]}}

        # When we have an existing object, lets unwrap it so the value maybe used by the caller.
        {true, {:ok, value}, _} when is_struct(value) ->
          {value,
           %{
             value
             | _document: %{doc | _path: path ++ [%{object_id: value._object_id, key: key}]}
           }}

        # Bare value
        {true, {:ok, value}, _} when not is_struct(value) ->
          {doc_object, value}
      end

    # Invoke the callback and from there figure out what to do; `:pop` or {existing_value, updated_value} is expected.
    {value, context} =
      case fun.(value) do
        :pop ->
          context = Context.delete_map_key(context, path, key)

          {nil, context}

        ## Check for references to existing objects

        # When the update value is nil so we aren't making an update so the doc we have is an reference to an existing
        # object which is unsupported.

        {nil, doc} when is_struct(doc, Automerge) or is_struct(doc, Document) ->
          raise "Cannot create a reference to an existing document object"

        {nil, doc}
        when (is_struct(doc, Automerge.Map) or is_struct(doc, Automerge.List) or
                is_struct(doc, Automerge.Text)) and not is_nil(doc._object_id) and
               is_nil(doc._document) ->
          raise "Cannot create a reference to an existing document object"

        {get, context} when is_struct(context, Context) ->
          {get, context}

        {get, document} when is_struct(document, Document) ->
          {get, document._context}

        ## Support Map, List, and Text functions that return an object with an updated context.

        {get, update} when is_struct(update, Automerge.Map) and not is_nil(update._document) ->
          {get, update._document._context}

        {get, update} when is_struct(update, Automerge.List) and not is_nil(update._document) ->
          {get, update._document._context}

        {get, update} when is_struct(update, Automerge.Text) and not is_nil(update._document) ->
          {get, update._document._context}

        ## This is where we begin the assumption game!

        {get, update} ->
          # We assume based on if there is a get value that get_and_update_in was used. If get_and_update_in was used we
          # will update the element instead of replacing it. `put_in` is destructive.
          is_update? = !is_nil(get) or is_tuple(update)

          # If were not doing an update the doc_object is what we'll want to check (such as if it's map or list)
          base_object = object

          # Check the object type so we know what context function to invoke later.
          object_type =
            cond do
              is_struct(base_object, Automerge.Map) -> "map"
              is_struct(base_object, Automerge.List) -> "list"
              true -> "map"
            end

          # We'll use the object type and if there is an existing get to call the appropriate function in Context
          case {object_type, is_update?} do
            # Looks like we'll be creating a new object
            {"map", false} ->
              context = Context.set_map_key!(context, path, key, update)

              {get, context}

            {"map", true} ->
              update =
                if is_tuple(update) do
                  {_, update} = update
                  update
                else
                  update
                end

              case update do
                update when is_struct(update, Automerge.Map) ->
                  context =
                    Enum.reduce(update._value, context, fn {update_key, value}, acc ->
                      Context.set_map_key!(
                        acc,
                        path ++ [%{object_id: object._object_id, key: key}],
                        update_key,
                        value
                      )
                    end)

                  {get, context}

                update when is_map(update) ->
                  context =
                    Enum.reduce(update, context, fn {update_key, value}, acc ->
                      Context.set_map_key!(
                        acc,
                        path ++ [%{object_id: object._object_id, key: key}],
                        update_key,
                        value
                      )
                    end)

                  {get, context}

                _ ->
                  context = Context.set_map_key!(context, path, key, update)

                  {get, context}
              end

            {"list", _} ->
              context = Context.set_map_key!(context, path, key, update)

              {get, context}
          end

        _resp ->
          raise "Not expected result."
      end

    {value, %{doc | _context: context, _object_id: object._object_id}}
  end

  @impl Access
  def pop(
        doc = %Document{_object_id: object_id, _context: context, _path: path},
        key,
        _default \\ nil
      ) do
    doc_object = Context.get_object!(context, object_id)

    fetch = Map.fetch(doc_object._value, key)

    {object, _value} =
      case fetch do
        :error ->
          {doc_object, nil}

        {:ok, value} when is_struct(value, Automerge.Map) or is_struct(value, Automerge.List) ->
          {value, value._value}

        {:ok, value} ->
          {doc_object, value}
      end

    object_type =
      if is_struct(object, Automerge.Map) do
        "map"
      else
        "list"
      end

    context =
      case object_type do
        "map" -> Context.delete_map_key(context, path, key)
      end

    {fetch, %{doc | _context: context}}
  end
end
