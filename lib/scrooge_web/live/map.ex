defmodule ScroogeWeb.Live.Map do
  @moduledoc "Live view for Tesla"
  use ScroogeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    attributes = %{
      since: "since",
      latitude: "latitude",
      longitude: "longitude",
      heading: "heading",
      speed: "speed",
      doors_open: "doors_open",
      trunk_open: "trunk_open",
      frunk_open: "frunk_open",
      windows_open: "windows_open",
      plugged_in: "plugged_in",
      geofence: "geofence",
      is_user_present: "is_user_present",
      locked: "locked",
      state: "state"
    }

    current_user = socket.assigns.current_user

    if ScroogeWeb.Auth.user_is_admin?(current_user) do
      for {key, name} <- attributes do
        MqttPotion.Multiplexer.subscribe_str(
          "teslamate/cars/1/#{name}",
          key,
          self(),
          :raw,
          :resend
        )
      end

      MqttPotion.Multiplexer.subscribe_str(
        "life360/#",
        :life360,
        self(),
        :json,
        :resend
      )
    end

    tesla =
      Enum.reduce(attributes, %{}, fn {key, _}, tesla ->
        Map.put(tesla, key, nil)
      end)

    socket =
      socket
      |> assign(:tesla, tesla)
      |> assign(:life360, %{})
      |> assign(:active, "map")

    {:ok, socket}
  end

  @impl true
  def handle_cast({:mqtt, _, :life360, payload}, socket) do
    id = payload["id"]

    life360 = Map.put(socket.assigns.life360, id, payload)

    socket =
      socket
      |> assign(:life360, life360)
      |> push_event("person", payload)

    {:noreply, socket}
  end

  def handle_cast({:mqtt, _, key, payload}, socket) do
    payload = decode(key, payload)

    tesla = Map.put(socket.assigns.tesla, key, payload)

    socket =
      socket
      |> assign(:tesla, tesla)
      |> push_event("tesla", tesla)

    {:noreply, socket}
  end

  defp float(value) do
    case Float.parse(value) do
      {v, ""} -> v
      _ -> nil
    end
  end

  defp integer(value) do
    case Integer.parse(value) do
      {v, ""} -> v
      _ -> :error
    end
  end

  defp boolean(value) do
    case value do
      "true" -> true
      "false" -> false
      _ -> :error
    end
  end

  defp string(value) do
    value
  end

  defp date_time(str) do
    {:ok, dt, 0} = DateTime.from_iso8601(str)
    dt
  end

  defp decode(:latitude, body), do: float(body)
  defp decode(:longitude, body), do: float(body)
  defp decode(:heading, body), do: integer(body)
  defp decode(:speed, body), do: integer(body)
  defp decode(:since, body), do: date_time(body)
  defp decode(:doors_open, body), do: boolean(body)
  defp decode(:trunk_open, body), do: boolean(body)
  defp decode(:frunk_open, body), do: boolean(body)
  defp decode(:windows_open, body), do: boolean(body)
  defp decode(:plugged_in, body), do: boolean(body)
  defp decode(:locked, body), do: boolean(body)
  defp decode(:is_user_present, body), do: boolean(body)
  defp decode(:geofence, body), do: string(body)
  defp decode(:state, body), do: string(body)
  defp decode(:battery_level, body), do: integer(body)
end
