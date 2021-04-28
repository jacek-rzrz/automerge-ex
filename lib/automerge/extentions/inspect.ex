defimpl Inspect, for: Automerge do
  import Inspect.Algebra
  @doc false
  def inspect(am, opts) do
    concat(["#Automerge<", to_doc(Automerge.get_document(am), opts), ">"])
  end
end

defimpl Inspect, for: Automerge.Frontend.Document do
  import Inspect.Algebra
  @doc false
  def inspect(doc, opts) do
    concat(["#Automerge<", to_doc(Automerge.get_document(doc), opts), ">"])
  end
end
