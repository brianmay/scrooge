defmodule ScroogeWeb.Live.Tesla do
  @moduledoc "Live view for Tesla"
  use Phoenix.LiveView

  def render(assigns) do
    ScroogeWeb.LiveView.render("tesla.html", assigns)
  end

  def mount(_params, _session, socket) do
    Scrooge.Tesla.register(self())
    tesla_state = Scrooge.Tesla.get_tesla_state()
    {:ok, assign(socket, :tesla_state, tesla_state)}
  end

  def handle_cast({:update_tesla_state, tesla_state}, socket) do
    {:noreply, assign(socket, :tesla_state, tesla_state)}
  end
end
