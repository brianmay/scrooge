defmodule ScroogeWeb.Live.Amber do
  use Phoenix.LiveView

  def render(assigns) do
    ScroogeWeb.LiveView.render("amber.html", assigns)
  end

  def mount(_params, _session, socket) do
    Scrooge.Amber.register(self())
    tesla_state = Scrooge.Amber.get_amber_state()
    {:ok, assign(socket, :amber_state, tesla_state)}
  end

  def handle_cast({:update_amber_state, tesla_state}, socket) do
    {:noreply, assign(socket, :amber_state, tesla_state)}
  end
end
