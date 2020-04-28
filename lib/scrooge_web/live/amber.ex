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
      |> assign(:period, nil)
      |> update_amber_state(amber_state)

    {:ok, socket}
  end

  def handle_cast({:update_amber_state, amber_state}, socket) do
    socket = update_amber_state(socket, amber_state)
    {:noreply, assign(socket, :amber_state, amber_state)}
  end

  def handle_event("meter", param, socket) do
    meter =
      case param["meter"] do
        "" -> nil
        meter -> meter
      end

    socket = assign(socket, :meter, meter)
    {:noreply, socket}
  end

  def handle_event("period", param, socket) do
    period =
      case param["period"] do
        "" ->
          nil

        period ->
          case DateTime.from_iso8601(period) do
            {:ok, dt, 0} -> dt
            _ -> nil
          end
      end

    period =
      cond do
        socket.assigns.period == nil -> period
        DateTime.compare(period, socket.assigns.period) == :eq -> nil
        true -> period
      end

    socket = assign(socket, :period, period)
    {:noreply, socket}
  end
end
