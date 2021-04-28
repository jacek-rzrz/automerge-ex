defmodule Automerge.Backend.NIF do
  use Rustler,
    otp_app: :automerge_backend_nif,
    crate: "automerge_backend_nif"

  defp err, do: :erlang.nif_error(:nif_not_loaded)

  def apply_changes(_backend, _changes), do: err()
  def apply_local_change(_backend, _change), do: err()

  def load_changes(_backend, _changes), do: err()

  def get_patch(_backend), do: err()
  def get_heads(_backend), do: err()

  def get_changes(_backend, _deps), do: err()
  def get_all_changes(_backend), do: err()

  def get_missing_deps(_backend), do: err()

  def init(), do: err()
  def load(_backend), do: err()
  def save(_backend), do: err()

  def free(_backend), do: err()
  def clone(_backend), do: err()

  def encode_change(_change), do: err()
  def decode_change(_change), do: err()
end
