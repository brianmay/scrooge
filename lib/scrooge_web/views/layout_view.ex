defmodule ScroogeWeb.LayoutView do
  use ScroogeWeb, :view

  def active_class(active, active), do: "active"
  def active_class(_, _), do: ""
end
