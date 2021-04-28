defmodule Automerge.Frontend do
  @moduledoc false

  alias Automerge
  alias Automerge.State

  alias Automerge.Frontend.{
    ApplyPatch,
    Context,
    Document
  }

  @root_id "_root"

  @spec update_root_object(Automerge.t(), any, any) :: Automerge.t()
  def update_root_object(doc, updated, state) do
    new_doc = get_in(updated, [@root_id])

    updated =
      if is_nil(new_doc) do
        doc_root = get_in(doc._cache, [@root_id])
        put_in(updated, [@root_id], doc_root)
      else
        updated
      end

    updated =
      doc._cache
      |> Map.keys()
      |> Enum.reduce(updated, fn object_id, acc ->
        if Map.get(acc, object_id) do
          acc
        else
          Map.put(acc, object_id, doc._cache[object_id])
        end
      end)

    %{doc | _cache: updated, _state: state}
  end

  def make_change!(doc, context, options \\ []) do
    actor_id = Automerge.get_actor_id(doc)

    if is_nil(actor_id) do
      raise "Actor ID must be initialized with set_actor_id() before making a change"
    end

    state = doc._state
    state = update_in(state.seq, &(&1 + 1))

    change = %{
      "actor" => actor_id,
      "seq" => state.seq,
      "startOp" => state.max_op + 1,
      "deps" => state.deps,
      "time" =>
        if options[:time] do
          options[:time]
        else
          "Etc/UTC"
          |> DateTime.now!()
          |> DateTime.to_unix()
        end,
      "message" =>
        if options[:message] do
          options[:message]
        else
          nil
        end,
      "ops" => context.ops
    }

    backend = get_in(doc._options, [:backend])

    if backend do
      {backend_state, patch, binary_change} =
        backend.apply_local_change(state.backend_state, change)

      state = %{state | backend_state: backend_state, last_local_change: binary_change}

      new_doc = apply_patch_to_doc!(doc, patch, state, true)
      # TODO(ts): patchCallback
      {new_doc, change}
    else
      queued_request = %{"actor" => actor_id, "seq" => Map.get(change, "seq"), "before" => doc}

      state = %{
        state
        | requests: state.requests ++ [queued_request],
          max_op: state.max_op + length(Map.get(change, "ops")),
          deps: []
      }

      {update_root_object(
         doc,
         if context do
           context.updated
         else
           %{}
         end,
         state
       ), change}
    end
  end

  def get_last_local_change(doc) do
    doc._state.last_local_change
  end

  def apply_patch_to_doc!(doc, patch, state, from_backend?) do
    actor_id = Automerge.get_actor_id(doc)

    context = %Context{
      actor_id: actor_id,
      max_op: doc._state.max_op,
      cache: doc._cache
    }

    context = ApplyPatch.interpret_patch(context, patch["diffs"], %{})

    if from_backend? do
      unless get_in(patch, ["clock"]) do
        raise "patch is missing clock field"
      end

      patch_clock = get_in(patch, ["clock", actor_id])

      seq =
        if !is_nil(patch_clock) and patch_clock > state.seq do
          patch_clock
        else
          state.seq
        end

      state = %{
        state
        | seq: seq,
          clock: patch["clock"],
          deps: patch["deps"],
          max_op: max(state.max_op || 0, patch["maxOp"] || 0)
      }

      update_root_object(doc, context.updated, state)
    else
      update_root_object(doc, context.updated, state)
    end
  end

  def init(options \\ [])

  def init(actor_id) when is_binary(actor_id) do
    init(actor_id: actor_id)
  end

  def init(options) do
    {from, options} = Keyword.pop(options, :from, nil)
    backend = Keyword.get(options, :backend)
    observable = Keyword.get(options, :observable)

    options =
      Keyword.merge(
        [
          actor_id:
            if options[:defer_actor_id] do
              nil
            else
              Automerge.check_actor_id!(options[:actor_id] || UUID.uuid4(:hex))
            end
        ],
        options
      )

    if observable do
      # TODO(ts): Implement
    end

    cache = %{@root_id => %Automerge.Map{_object_id: @root_id, _value: %{}}}
    state = %State{}

    state =
      if backend do
        %{state | backend_state: backend.init()}
      else
        state
      end

    root = %Automerge{
      _object_id: @root_id,
      _options: options,
      _conflicts: %{},
      _cache: cache,
      _state: state
    }

    if from do
      # Implement from
      {doc, _changes} =
        Automerge.change!(
          root,
          [message: "Initialization"],
          &Map.merge(&1, from)
        )

      doc
    else
      root
    end
  end

  def from(initial_state, options) do
    options
    |> init()
    |> change!([message: Initialization], &Map.merge(&1, initial_state))
  end

  def change!(doc, callback) when is_function(callback, 1) do
    change!(doc, [], callback)
  end

  def change!(doc, options, callback) when is_struct(doc, Automerge) do
    actor_id = Automerge.get_actor_id(doc)

    document = Document.object_proxy(doc, actor_id)

    # How is context derived from the client?
    callback_doc = callback.(document)

    unless is_struct(callback_doc, Document) do
      raise "Document has to be returned from callback"
    end

    # Elixir's Map module can modify structs. Were we pull the keys off the struct that aren't valid to raise
    assigned =
      callback_doc
      |> Map.from_struct()
      |> Enum.reject(fn {key, _value} ->
        key in [:_object_id, :_path, :_context]
      end)

    callback_doc = %Document{
      _object_id: callback_doc._object_id,
      _path: callback_doc._path,
      _context: callback_doc._context
    }

    {doc, _changes} =
      if Enum.empty?(assigned) do
        {doc, nil}
      else
        change!(doc, options, fn doc ->
          Enum.reduce(assigned, doc, fn {key, value}, acc ->
            update_in(acc, callback_doc._path ++ [key], fn _ -> value end)
          end)
        end)
      end

    is_changed? = document != callback_doc

    if is_changed? do
      make_change!(doc, callback_doc._context, options)
    else
      {doc, nil}
    end
  end

  def empty_change!(doc, options) when is_binary(options) do
    empty_change!(doc, message: options)
  end

  def empty_change!(doc, options) do
    actor_id = Automerge.get_actor_id(doc)

    unless actor_id do
      raise "Actor ID must be initialized with setActorId() before making a change"
    end

    context = %Context{
      actor_id: actor_id,
      max_op: doc._state.max_op,
      cache: doc._cache,
      updated: %{}
    }

    make_change!(doc, context, options)
  end

  def apply_patch!(doc, patch) do
    state = doc._state

    if get_in(doc._options, [:backend]) do
      unless get_in(patch, ["state"]) do
        raise "When an immediate backend is used, a patch must contain the new backend state"
      end

      state = %{state | backend_state: patch["state"]}

      apply_patch_to_doc!(doc, patch, state, true)
    else
      {doc, state} =
        if Enum.count(state.requests) > 0 do
          before_doc = get_in(state.requests, [Access.at(0), "before"])

          if patch["actor"] === Automerge.get_actor_id(doc) do
            if get_in(state.requests, [Access.at(0), "seq"]) !== patch["seq"] do
              raise "Mismatched sequence number: patch #{patch["seq"]} does not match next request}"
            end

            {before_doc, put_in(state.requests, tl(state.requests))}
          else
            {before_doc, state}
          end
        else
          {doc, put_in(state.requests, [])}
        end

      new_doc = apply_patch_to_doc!(doc, patch, state, true)
      state = new_doc._state

      if state.requests === [] do
        new_doc
      else
        requests =
          update_in(state.requests, [Access.at(0)], fn request ->
            Map.merge(request, %{"before" => new_doc})
          end)

        state = %{state | requests: requests}

        update_root_object(new_doc, %{}, state)
      end
    end
  end

  def get_object_by_id(_doc, _object_id) do
    # TODO(ts): Implement
  end

  @spec get_backend_state(Automerge.t()) :: any
  def get_backend_state(doc) do
    doc._state.backend_state
  end

  def get_element_ids(list) when is_struct(list, Automerge.List) do
    list._elem_ids
  end

  def get_element_ids(list) when is_struct(list, Automerge.Text) do
    Enum.map(list._elems, & &1.elem_id)
  end
end
