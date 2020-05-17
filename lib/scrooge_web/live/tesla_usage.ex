defmodule ScroogeWeb.Live.TeslaUsage do
  use Phoenix.LiveView

  import Ecto.Query

  def render(assigns) do
    ScroogeWeb.LiveView.render("tesla_usage.html", assigns)
  end

  def mount(_params, _session, socket) do
    Scrooge.Tesla.register(self())
    tesla_state = Scrooge.Tesla.get_tesla_state()
    amber_state = Scrooge.Amber.get_amber_state()

    socket =
      socket
      |> assign(:tesla_state, tesla_state)
      |> assign(:amber_state, amber_state)
      |> update_tesla_history()

    {:ok, socket}
  end

  defp get_price_at_time(dt, amber_state) do
    the_time =
      amber_state["variablePricesAndRenewables"]
      |> Enum.filter(fn row -> DateTime.compare(row["period"], dt) == :eq end)

    case the_time do
      [a] -> a["prices"]["E1"].total_gst_price
      _ -> nil
    end
  end

  defp update_tesla_history(socket) do
    {:ok, now} = DateTime.now("Etc/UTC")
    start = DateTime.add(now, -(60 * 60 * 24))
    stop = now

    tesla_history =
      Scrooge.History
      |> group_by([e], fragment("rounded_time"))
      |> where([e], e.date_time >= ^start and e.date_time < ^stop)
      |> select([e], %{
        rounded_time:
          fragment(
            "date_trunc('hour', ?) + date_part('minute', ?)::int / 30 * interval '30 min' as rounded_time",
            e.date_time,
            e.date_time
          ),
        count: count(e.id),
        delta_time: sum(e.delta_time),
        delta_odometer: sum(e.delta_odometer),
        delta_charge_energy_added: sum(e.delta_charge_energy_added)
      })
      |> Scrooge.TeNerves.all()
      |> Enum.map(fn entry ->
        dt = DateTime.from_naive!(entry.rounded_time, "Etc/UTC")
        cents_per_kwh = get_price_at_time(dt, socket.assigns.amber_state)

        total_cents =
          case cents_per_kwh do
            nil -> nil
            cents_per_kwh -> cents_per_kwh * entry.delta_charge_energy_added
          end

        Map.merge(entry, %{
          rounded_time: dt,
          cents_per_kwh: cents_per_kwh,
          total_cents: total_cents
        })
      end)

    {total_count, total_time, total_odometer, total_charge_energe_added, total_cents} =
      Enum.reduce(tesla_history, {0, 0, 0.0, 0.0, 0.0}, fn
        entry, {count, time, odometer, charge_energy_added, total_cents} ->
          count = count + entry.count
          time = time + entry.delta_time
          odometer = odometer + entry.delta_odometer
          charge_energy_added = charge_energy_added + entry.delta_charge_energy_added

          total_cents =
            case entry.total_cents do
              nil -> total_cents
              value -> total_cents + value
            end

          {count, time, odometer, charge_energy_added, total_cents}
      end)

    tesla_totals = %{
      total_count: total_count,
      total_time: total_time,
      total_odometer: total_odometer,
      total_charge_energy_added: total_charge_energe_added,
      total_cents: total_cents
    }

    socket
    |> assign(:tesla_history, tesla_history)
    |> assign(:tesla_totals, tesla_totals)
  end

  def handle_cast({:update_tesla_state, tesla_state}, socket) do
    socket =
      socket
      |> assign(:tesla_state, tesla_state)
      |> update_tesla_history()

    {:noreply, socket}
  end

  def handle_cast({:update_amber_state, amber_state}, socket) do
    socket =
      socket
      |> assign(:amber_state, amber_state)
      |> update_tesla_history()

    {:noreply, socket}
  end
end
