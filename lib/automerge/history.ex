defmodule Automerge.History do
  @moduledoc """
  A representation of the history of an automerge document.
  """
  defstruct change_callback: nil, snapshot_callback: nil

  @opaque t() :: {}

  alias Automerge.History

  def get_change!(%History{change_callback: callback}) when is_function(callback) do
    callback.()
  end

  def get_change!(_history), do: raise("Invalid historical state")

  def get_snapshot!(%History{snapshot_callback: callback}) when is_function(callback) do
    callback.()
  end

  def get_snapshot!(_history), do: raise("Invalid historical state")
end
