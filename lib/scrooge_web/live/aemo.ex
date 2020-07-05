defmodule ScroogeWeb.Live.Aemo do
  use Phoenix.LiveView

  def render(assigns) do
    ScroogeWeb.LiveView.render("aemo.html", assigns)
  end

  defp update_aemo_state(socket, aemo_state) do
    meters = ["E1"]

    meter = socket.assigns.meter

    meter =
      cond do
        is_nil(meter) -> nil
        Enum.member?(meters, meter) -> meter
        true -> nil
      end

    socket
    |> assign(:aemo_state, aemo_state)
    |> assign(:meters, meters)
    |> assign(:meter, meter)
  end

  def mount(_params, _session, socket) do
    Scrooge.Aemo.register(self())
    aemo_state = Scrooge.Aemo.get_aemo_state()

    socket =
      socket
      |> assign(:meter, "E1")
      |> assign(:period, nil)
      |> update_aemo_state(aemo_state)

    {:ok, socket}
  end

  def handle_cast({:update_aemo_state, aemo_state}, socket) do
    socket = update_aemo_state(socket, aemo_state)
    {:noreply, assign(socket, :aemo_state, aemo_state)}
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
