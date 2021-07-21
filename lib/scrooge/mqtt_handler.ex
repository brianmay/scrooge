defmodule Scrooge.MqttHandler do
  @moduledoc false
  @behaviour MqttPotion.Handler

  require Logger

  @impl MqttPotion.Handler
  def handle_connect do
    Logger.info("MQTT Connection has been established")
    :ok
  end

  @impl MqttPotion.Handler
  def handle_disconnect(_reason, _properties) do
    Logger.warn("MQTT Connection has been dropped")
    :ok
  end

  @impl MqttPotion.Handler
  def handle_puback(_ack) do
    :ok
  end

  @impl MqttPotion.Handler
  def handle_message(["teslamate", "cars", "1" | topic], message) do
    Logger.debug("handle message #{message.topic} #{inspect(message)}")
    utc_now = DateTime.utc_now()

    case decode(topic, message.payload) do
      {key, :error} ->
        Logger.error("Invalid #{inspect(key)} value #{inspect(message)} received")

      {key, value} ->
        Logger.debug("Got #{inspect(key)} #{inspect(message)} #{inspect(value)}")
        Scrooge.Tesla.update_tesla_state(utc_now, key, value)

      nil ->
        nil
    end

    :ok
  end

  @impl MqttPotion.Handler
  def handle_message(_topic, message) do
    Logger.info("#{message.topic} #{inspect(message)} unknown message")
    :ok
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

  defp decode(["latitude"], body), do: {:latitude, float(body)}
  defp decode(["longitude"], body), do: {:longitude, float(body)}
  defp decode(["heading"], body), do: {:heading, integer(body)}
  defp decode(["speed"], body), do: {:speed, integer(body)}
  defp decode(["since"], body), do: {:since, date_time(body)}
  defp decode(["doors_open"], body), do: {:doors_open, boolean(body)}
  defp decode(["trunk_open"], body), do: {:trunk_open, boolean(body)}
  defp decode(["frunk_open"], body), do: {:frunk_open, boolean(body)}
  defp decode(["windows_open"], body), do: {:windows_open, boolean(body)}
  defp decode(["plugged_in"], body), do: {:plugged_in, boolean(body)}
  defp decode(["locked"], body), do: {:locked, boolean(body)}
  defp decode(["is_user_present"], body), do: {:is_user_present, boolean(body)}
  defp decode(["geofence"], body), do: {:geofence, string(body)}
  defp decode(["battery_level"], body), do: {:battery_level, integer(body)}
  defp decode(_, _), do: nil
end
