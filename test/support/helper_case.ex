defmodule Automerge.HelperCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Automerge.HelperCase
    end
  end

  def uuid(), do: UUID.uuid4(:hex)
end
