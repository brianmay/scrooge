defmodule ScroogeWeb.Live.Tesla do
  @moduledoc "Live view for Tesla"
  use Phoenix.LiveView

  import ScroogeWeb.LiveHelpers

  def render(assigns) do
    ScroogeWeb.LiveView.render("tesla.html", assigns)
  end

  def mount(_params, session, socket) do
    socket = assign_defaults(socket, session)
    Scrooge.Tesla.register(self())
    {active_conditions, tesla_state} = Scrooge.Tesla.get_tesla_state()

    socket =
      socket
      |> assign(:tesla_state, tesla_state)
      |> assign(:active_conditions, active_conditions)
      |> assign(:active, "tesla")

    {:ok, socket}
  end

  def handle_cast({:update_tesla_state, active_conditions, tesla_state}, socket) do
    socket = assign(socket, :tesla_state, tesla_state)
    socket = assign(socket, :active_conditions, active_conditions)
    {:noreply, socket}
  end
end
