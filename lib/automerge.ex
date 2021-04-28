defmodule Automerge do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias Automerge.{Frontend, History, State, Text}
  alias Automerge.Frontend.Document

  @behaviour Access

  @root_id "_root"

  # Default backend is a NIF binding to https://github.com/automerge/automerge-rs (via Rustler, see automerge_backend_nif)
  @backend Application.compile_env(:automerge, :backend, Automerge.Backend.NIF)

  defmodule State do
    @moduledoc false
    defstruct actor_id: nil,
              seq: 0,
              max_op: 0,
              requests: [],
              deps: [],
              clock: %{},
              backend_state: nil,
              last_local_change: nil

    @type t() :: {
            seq :: integer(),
            requests :: list(),
            deps :: list(),
            can_undo :: boolean(),
            can_redo :: boolean(),
            backend_state :: Automerge.Backend.t()
          }
  end

  @typedoc "Automerge document"
  @opaque t() :: {
            _object_id :: String.t(),
            _options :: list(),
            _conflicts :: map(),
            _cache :: map(),
            _state :: State.t(),
            _updated :: map()
          }

  @typep counter() :: {}
  @typep text() :: {}
  @typep table() :: {}
  @typep object() :: {}
  @typep l() :: {}

  @typedoc "Counter, Text, Table, List, or Object"
  @type types() :: counter() | text() | table() | object() | l()

  defstruct _object_id: nil,
            _options: [],
            _conflicts: %{},
            _cache: %{},
            _state: nil,
            _path: []

  # TODO(ts): Types for patch and diffs?

  ## Access behaviour

  @doc false
  @impl Access
  def fetch(doc = %Automerge{}, key) do
    actor_id = UUID.uuid4()

    doc_root =
      Document.object_proxy(
        doc,
        actor_id,
        if doc._path == [] do
          @root_id
        else
          doc._object_id
        end
      )

    case Access.fetch(doc_root, key) do
      nil ->
        :error

      # If we get back a document, keep traversing
      {:ok, document} when is_struct(document, Document) ->
        case get_in(document._context.cache, [document._object_id]) do
          nil ->
            :error

          resp ->
            {:ok, resp}
        end

      {:ok, value} when is_struct(value, Automerge.List) or is_struct(value, Automerge.Text) ->
        {:ok, value}

      # Root object
      {:ok, _value} ->
        {:ok, doc._cache["_root"]}
    end
  end

  @doc false
  @impl Access
  def get_and_update(_doc, _key, _fun) do
    raise "Can only modify the document inside of change!/2 or change!/3 callback"
  end

  @doc false
  @impl Access
  def pop(_doc, _key, _default \\ nil) do
    raise "Can only modify the document inside of change!/2 or change!/3 callback"
  end

  ## API

  @doc ~S"""
  Initialize a new document.

  ## Options

    * `:actor_id` - A hex
    * `:defer_actor_id` - `true|false` if to defer assigning an actor_id, meant to be set later via `Automerge.set_actor_id/2`. If set, some functions may raise if an actor_id is not assigned.

    If the list is omitted and a string is passed for the `opts` argument the string will be applied as the `actor_id`.
  """
  @spec init(keyword) :: Automerge.t() | {:error, String.t()}
  def init(args \\ [])

  def init(args) when is_binary(args) do
    Frontend.init(actor_id: args, backend: @backend)
  end

  def init(args) when is_list(args) do
    {backend, args} = Keyword.pop(args, :backend, @backend)

    [backend: backend]
    |> Keyword.merge(args)
    |> Frontend.init()
  end

  @doc ~S"""
  Given a initial state, initializes a new document.

  ## Examples

      iex> Automerge.from!(%{"birds" => Automerge.list(["chaffinch"])})
      #Automerge<%{"birds" => ["chaffinch"]}>

      iex> Automerge.from!(%{"number" => 1}, actor_id: UUID.uuid4(:hex))
      #Automerge<%{"number" => 1}>

  ## Options

  See `Automerge.init/1` options.
  """
  @spec from!(map(), keyword()) :: Automerge.t()
  @doc section: :change
  def from!(state, opts \\ [])

  def from!(initial_state, opts) do
    # Preprocess the initial state to check for specific cases. Namely, to see if we have a string, a bare list, a
    # bare boolean, or an illegal Elixir atomic. The jest of this preprocessing is to mimic Object.assigns({}, value).
    initial_state =
      case initial_state do
        initial_state when is_map(initial_state) ->
          initial_state

        initial_state when is_list(initial_state) ->
          initial_state
          |> Enum.with_index()
          |> Enum.map(fn {value, key} -> {Integer.to_string(key), value} end)
          |> Enum.into(%{})

        initial_state when is_binary(initial_state) ->
          initial_state
          |> String.graphemes()
          |> Enum.with_index()
          |> Enum.map(fn {value, index} -> {Integer.to_string(index), value} end)
          |> Enum.into(%{})

        initial_state when is_boolean(initial_state) ->
          # Hmm(ts): I really think this should raise but to match the JS library; just ignore. Same with number.
          :ignore

        initial_state when is_number(initial_state) ->
          :ignore

        _ ->
          raise "Invalid type passed as initial state"
      end

    if initial_state != :ignore do
      {doc, _change} =
        Automerge.change!(
          init(opts),
          [message: "Initialization"],
          &Map.merge(&1, initial_state)
        )

      doc
    else
      init(opts)
    end
  end

  @doc ~S"""
  Modify a document by a given callback.

  ## Examples

      iex> {doc, _change} = Automerge.change!(Automerge.from!(%{"birds" => Automerge.list(["chaffinch"])}), fn doc ->
      ...>  update_in(doc["birds"], &Automerge.List.append(&1, ["goldfinch"]))
      ...> end)
      iex> doc
      #Automerge<%{"birds" => ["chaffinch", "goldfinch"]}>
  """
  @spec change!(Automerge.t(), (Document.t() -> Document.t())) :: Automerge.t()
  @doc section: :change
  def change!(doc, callback) when is_function(callback, 1) do
    change!(doc, [], callback)
  end

  @doc ~S"""
  Modify a document by a given callback.

  ## Examples

      iex> {doc, _change} = Automerge.change!(Automerge.from!(%{"birds" => Automerge.list(["chaffinch"])}), "Adding a new bird", fn doc ->
      ...>  update_in(doc["birds"], &Automerge.List.append(&1, ["goldfinch"]))
      ...> end)
      iex> doc
      #Automerge<%{"birds" => ["chaffinch", "goldfinch"]}>

      iex> {doc, _change} = Automerge.change!(Automerge.from!(%{"birds" => Automerge.list(["chaffinch"])}), [message: "Adding a new bird"], fn doc ->
      ...>  update_in(doc["birds"], &Automerge.List.append(&1, ["goldfinch"]))
      ...> end)
      iex> doc
      #Automerge<%{"birds" => ["chaffinch", "goldfinch"]}>

  ## Options

    * `:message` - An optional descriptive string that is attached to the change.

  If the list is omitted and a string is passed for the `opts` argument the string will be applied as the `message`.
  """
  @spec change!(Automerge.t(), keyword(), (Document.t() -> Document.t())) :: Automerge.t()
  @doc section: :change
  def change!(doc, opts, callback) when is_function(callback, 1) and is_list(opts) do
    Frontend.change!(doc, opts, callback)
  end

  def change!(doc, opts, callback) when is_function(callback, 1) and is_binary(opts) do
    Frontend.change!(doc, [message: opts], callback)
  end

  @doc ~S"""
  Create an empty change request on the document.

  Useful for acknowledging the receipt of a message.

  ## Options

  See `Automerge.change!/3` for options.
  """
  @spec empty_change(Automerge.t(), keyword()) :: Automerge.t()
  @doc section: :change
  def empty_change(doc, opts \\ [])

  def empty_change(doc, opts) do
    {doc, _change} = Frontend.empty_change!(doc, opts)

    doc
  end

  def clone(doc) do
    state = @backend.clone(Frontend.get_backend_state(doc))
    patch = @backend.get_patch(state)

    put_in(patch, "state", state)

    Frontend.apply_patch!(Automerge.init(), patch)
  end

  def free(doc) do
    @backend.free(Frontend.get_backend_state(doc))
  end

  @doc ~S"""
  Load a document from an byte array.

  ## Options

  See `Automerge.init/1` options.
  """
  def load(data, opts \\ []) do
    state = @backend.load(data)
    patch = @backend.get_patch(state)
    patch = Map.put(patch, "state", state)

    opts =
      if is_binary(opts) do
        [actor_id: opts]
      else
        opts
      end

    doc =
      opts
      |> init()
      |> Frontend.apply_patch!(patch)

    patch_callback = Keyword.get(opts, :patch_callback, doc._options[:patch_callback])

    if patch_callback do
      # TODO(ts): Implement
      doc
    else
      doc
    end
  end

  @doc ~S"""
  Serialize the current document state into a single byte array.
  """
  def save(doc) do
    doc
    |> Frontend.get_backend_state()
    |> @backend.save()
  end

  @doc """
  Apply the changes of one document to another.


  """
  @spec merge!(Automerge.t(), Automerge.t()) :: Automerge.t()
  def merge!(local_doc, remote_doc) do
    if get_actor_id(local_doc) === get_actor_id(remote_doc) do
      raise "Cannot merge an actor with itself"
    end

    apply_changes(local_doc, get_all_changes(remote_doc))
  end

  @doc ~S"""
  """
  @spec get_changes(Automerge.t(), Automerge.t()) :: any()
  def get_changes(old_doc, new_doc) do
    old_state = Frontend.get_backend_state(old_doc)
    new_state = Frontend.get_backend_state(new_doc)

    @backend.get_changes(new_state, @backend.get_heads(old_state))
  end

  @doc ~S"""
  """
  @spec get_all_changes(Automerge.t()) :: any()
  def get_all_changes(doc) do
    doc
    |> Frontend.get_backend_state()
    |> @backend.get_all_changes()
  end

  def get_last_local_change(doc) do
    doc._state.last_local_change
  end

  @doc ~S"""
  """
  @spec apply_changes(Automerge.t(), any()) :: any()
  def apply_changes(doc, changes, options \\ []) do
    old_state = Frontend.get_backend_state(doc)
    {new_state, patch} = @backend.apply_changes(old_state, changes)

    patch = Map.put(patch, "state", new_state)

    new_doc = Frontend.apply_patch!(doc, patch)

    patch_callback = Keyword.get(options, :patch_callback, doc._options[:patch_callback])

    if patch_callback do
      # TODO(ts): Implement
      new_doc
    else
      new_doc
    end
  end

  @doc ~S"""
  Gets the change hashes of the changes with missing deps.

  Returns an empty list if no deps are missing.
  """
  @spec get_missing_deps(Automerge.t()) :: any()
  def get_missing_deps(doc) do
    doc
    |> Frontend.get_backend_state()
    |> @backend.get_missing_deps()
  end

  @doc ~S"""
  """
  def equals?(_left, _right) do
    # TODO(ts): Implement
  end

  @doc """
  """
  @spec get_history(Automerge.t()) :: any()
  def get_history(doc) do
    actor = get_actor_id(doc)

    case get_all_changes(doc) do
      [] ->
        []

      history ->
        history
        |> Enum.with_index()
        |> Enum.map(fn {change, index} ->
          %History{
            change_callback: fn ->
              @backend.decode_change(change)
            end,
            snapshot_callback: fn ->
              state = @backend.load_changes(@backend.init(), Enum.slice(history, 0, index + 1))
              patch = @backend.get_patch(state)

              patch = Map.put(patch, "state", state)

              Frontend.apply_patch!(init(actor), patch)
            end
          }
        end)
    end
  end

  @doc false
  def set_default_backend(_new_backend) do
    # Set `config :automerge, :backend, <module>` to specify a new backend and run
    # `mix deps.compile automerge` to recompile
    raise "Unsupported to specify backend during runtime, specify via mix config instead"
  end

  ## Util functions

  @doc """
  Retrieve the actor id the document represents.

  ## Examples

      iex> doc = Automerge.init("c2cf55d18137445eafa15af2b2ff4a06")
      iex> Automerge.get_actor_id(doc)
      "c2cf55d18137445eafa15af2b2ff4a06"
  """
  @spec get_actor_id(Automerge.t()) :: String.t()
  def get_actor_id(doc) do
    doc._state.actor_id || get_in(doc._options, [:actor_id])
  end

  @doc """
  Set the actor id for the document.

      iex> doc = Automerge.init(defer_actor_id: true)
      iex> Automerge.get_actor_id(doc)
      nil
      iex> doc = Automerge.set_actor_id(doc, "c2cf55d18137445eafa15af2b2ff4a06")
      iex> Automerge.get_actor_id(doc)
      "c2cf55d18137445eafa15af2b2ff4a06"

  """
  @spec set_actor_id(Automerge.t(), String.t()) :: Automerge.t()
  def set_actor_id(doc, actor_id) do
    check_actor_id!(actor_id)
    state = %{doc._state | actor_id: actor_id}
    Frontend.update_root_object(doc, %{}, state)
  end

  @doc """
  Get the object id for a given object.

  ## Examples

      iex> doc = Automerge.from!(%{"birds" => %{"wrens" => 3}})
      iex> Automerge.get_object_id(doc["birds"]["wrens"])
  """
  @spec get_object_id(types()) :: String.t() | nil
  def get_object_id(%_{_object_id: object_id}), do: object_id

  @doc ~S"""
  """
  @spec get_conflicts(Automerge.t(), list(String.t() | number())) :: map() | nil
  def get_conflicts(doc, field_path) when is_list(field_path) do
    obj =
      if Enum.count(field_path) == 1 do
        doc._cache[@root_id]
      else
        get_in(doc, field_path)
      end

    case obj do
      nil ->
        nil

      %Automerge.Map{_conflicts: conflicts} when conflicts != %{} ->
        last_key = Enum.reverse(field_path) |> hd()

        if Map.get(conflicts, last_key, %{}) |> Map.keys() |> Enum.count() > 1 do
          for {index, val} <- Map.get(conflicts, last_key, %{}), reduce: %{} do
            acc -> Map.put(acc, index, object_value(val))
          end
        else
          nil
        end

      %Automerge.List{_conflicts: conflicts} when conflicts != %{} ->
        last_key = Enum.reverse(field_path) |> hd()

        if Map.get(conflicts, last_key, %{}) |> Map.keys() |> Enum.count() > 1 do
          for {index, val} <- Map.get(conflicts, last_key, %{}), reduce: %{} do
            acc -> Map.put(acc, index, object_value(val))
          end
        else
          nil
        end

      %_{_object_id: object_id, _value: value}
      when object_id == nil or (object_id == "_root" and value == %{}) ->
        nil
    end
  end

  def get_conflicts(_doc, field_path), do: raise("Expects a list got #{field_path}")

  @doc """
  Get the underlying document value as an Elixir value.

  ## Examples

      iex> doc = Automerge.from!(%{"birds" => Automerge.list(["chaffinch"])})
      iex> Automerge.get_document(doc)
      %{"birds" => ["chaffinch"]}
  """
  @spec get_document(Automerge.t()) :: map()
  def get_document(doc) when is_struct(doc, Automerge) do
    root = doc._cache[@root_id]

    object_value(root)
  end

  def get_document(doc) when is_struct(doc, Automerge.Frontend.Document) do
    root = doc._context.cache[@root_id]

    get_object_value(doc, root)
  end

  def get_object_value(doc, object) when is_struct(object, Automerge.Map) do
    updated =
      if is_struct(doc, Automerge.Frontend.Document) do
        doc._context.updated
      else
        doc._updated
      end

    latest = Map.get(updated, object._object_id, object)

    Enum.reduce(latest._value, %{}, fn {key, value}, acc ->
      if is_struct(value) do
        Map.put(acc, key, get_object_value(doc, value))
      else
        Map.put(acc, key, value)
      end
    end)
  end

  def get_object_value(doc, object) when is_struct(object, Automerge.List) do
    updated =
      if is_struct(doc, Automerge.Frontend.Document) do
        doc._context.updated
      else
        doc._updated
      end

    latest = Map.get(updated, object._object_id, object)

    length = map_size(latest._value)

    range_end =
      if length > 0 do
        length - 1
      else
        0
      end

    if length > 0 do
      for index <- 0..range_end, reduce: [] do
        acc ->
          val = Map.get(latest._value, index)

          if is_struct(val) do
            List.insert_at(acc, index, get_object_value(doc, val))
          else
            List.insert_at(acc, index, val)
          end
      end
    else
      []
    end
  end

  def get_object_value(doc, object) when is_struct(object, Automerge.Text) do
    updated =
      if is_struct(doc, Automerge.Frontend.Document) do
        doc._context.updated
      else
        doc._updated
      end

    latest = Map.get(updated, object._object_id, object)

    to_string(latest)
  end

  def get_object_value(_doc, object) when is_struct(object, Automerge.Text.Elem) do
    to_string(object)
  end

  @doc false
  def object_value(object) when is_struct(object, Automerge.Map) do
    Enum.reduce(object._value, %{}, fn {key, value}, acc ->
      if is_struct(value) do
        Map.put(acc, key, object_value(value))
      else
        Map.put(acc, key, value)
      end
    end)
  end

  @doc false
  def object_value(object) when is_struct(object, Automerge.List) do
    length = map_size(object._value)

    range_end =
      if length > 0 do
        length - 1
      else
        0
      end

    if length > 0 do
      for index <- 0..range_end, reduce: [] do
        acc ->
          val = Map.get(object._value, index)

          if is_struct(val) do
            List.insert_at(acc, index, object_value(val))
          else
            List.insert_at(acc, index, val)
          end
      end
    else
      []
    end
  end

  def object_value(object) when is_struct(object, Text) do
    length = map_size(object._elems)

    range_end =
      if length > 0 do
        length - 1
      else
        0
      end

    if length > 0 do
      for index <- 0..range_end, reduce: [] do
        acc ->
          val = Map.get(object._elems, index)

          if is_struct(val) do
            List.insert_at(acc, index, object_value(val))
          else
            List.insert_at(acc, index, to_string(val))
          end
      end
    else
      []
    end
  end

  def object_value(object) when is_struct(object, Text.Elem) do
    if is_struct(object.value) do
      object_value(object.value)
    else
      object.value
    end
  end

  def object_value(val), do: val

  @doc false
  def check_actor_id!(actor_id) when is_binary(actor_id) do
    unless Regex.match?(~r{^[0-9a-f]+$}, actor_id) do
      raise "actorId must consist only of lowercase hex digits"
    end

    unless rem(String.length(actor_id), 2) == 0 do
      raise "actorId must consist of an even number of digits"
    end

    actor_id
  end

  def check_actor_id!(_actor_id),
    do: raise("Unsupported type of actorId")

  ## Types

  @spec text() :: Automerge.text()
  def text(text \\ nil), do: Text.text(text)

  @spec list() :: Automerge.list()
  def list(list \\ nil), do: Automerge.List.list(list)
end
