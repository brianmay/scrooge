defmodule Scrooge.MqttHandler do
  @moduledoc false

  require Logger

  use Tortoise.Handler

  defstruct []
  alias __MODULE__, as: State

  def init(_opts) do
    Logger.info("Initializing handler")
    {:ok, %State{}}
  end

  def connection(:up, state) do
    Logger.info("Connection has been established")
    {:ok, state}
  end

  def connection(:down, state) do
    Logger.warn("Connection has been dropped")
    {:ok, state}
  end

  def connection(:terminating, state) do
    Logger.warn("Connection is terminating")
    {:ok, state}
  end

  def subscription(:up, topic, state) do
    Logger.info("Subscribed to #{topic}")
    {:ok, state}
  end

  def subscription({:warn, [requested: req, accepted: qos]}, topic, state) do
    Logger.warn("Subscribed to #{topic}; requested #{req} but got accepted with QoS #{qos}")
    {:ok, state}
  end

  def subscription({:error, reason}, topic, state) do
    Logger.error("Error subscribing to #{topic}; #{inspect(reason)}")
    {:ok, state}
  end

  def subscription(:down, topic, state) do
    Logger.info("Unsubscribed from #{topic}")
    {:ok, state}
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

  def handle_message(["teslamate", "cars", "1" | topic], publish, state) do
    utc_now = DateTime.utc_now()

    case decode(topic, publish) do
      {key, :error} ->
        Logger.info("Invalid #{inspect(key)} value #{inspect(publish)} received")

      {key, value} ->
        Logger.debug("Got #{inspect(key)} #{inspect(publish)} #{inspect(value)}")
        Scrooge.Tesla.update_tesla_state(utc_now, key, value)

      nil ->
        nil
    end

    {:ok, state}
  end

  def handle_message(topic, publish, state) do
    Logger.info("#{Enum.join(topic, "/")} #{inspect(publish)} unknown message")
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.warn("Client has been terminated with reason: #{inspect(reason)}")
    :ok
  end
end
