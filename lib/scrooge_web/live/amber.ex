defmodule ScroogeWeb.Live.Amber do
  use Phoenix.LiveView

  def render(assigns) do
    ScroogeWeb.LiveView.render("amber.html", assigns)
  end

  defp update_amber_state(socket, amber_state) do
    meters =
      case amber_state do
        nil -> []
        data -> Map.keys(data["staticPrices"])
      end

    meter = socket.assigns.meter

    meter =
      cond do
        is_nil(meter) -> nil
        Enum.member?(meters, meter) -> meter
        true -> nil
      end

    socket
    |> assign(:amber_state, amber_state)
    |> assign(:meters, meters)
    |> assign(:meter, meter)
  end

  def mount(_params, _session, socket) do
    Scrooge.Amber.register(self())
    amber_state = Scrooge.Amber.get_amber_state()

    socket =
      socket
      |> assign(:meter, "E1")
      |> update_amber_state(amber_state)

    {:ok, socket}
  end

  def handle_cast({:update_amber_state, amber_state}, socket) do
    socket = update_amber_state(socket, amber_state)
    {:noreply, assign(socket, :amber_state, amber_state)}
  end

  def handle_event("meter", param, socket) do
    socket = assign(socket, :meter, param["meter"])
    {:noreply, socket}
  end
end
