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

  defp date_time(str) do
    {:ok, dt, 0} = DateTime.from_iso8601(str)
    dt
  end

  defp decode(["latitude"], message), do: {:latitude, float(message)}
  defp decode(["longitude"], message), do: {:longitude, float(message)}
  defp decode(["heading"], message), do: {:heading, integer(message)}
  defp decode(["speed"], message), do: {:speed, integer(message)}
  defp decode(["since"], message), do: {:since, date_time(message)}
  defp decode(["geofence"], message), do: {:geofence, message}
  defp decode(["doors_open"], message), do: {:doors_open, boolean(message)}
  defp decode(["trunk_open"], message), do: {:trunk_open, boolean(message)}
  defp decode(["frunk_open"], message), do: {:frunk_open, boolean(message)}
  defp decode(["windows_open"], message), do: {:windows_open, boolean(message)}
  defp decode(["plugged_in"], message), do: {:plugged_in, boolean(message)}
  defp decode(_, _), do: nil

  def handle_message(["teslamate", "cars", "1" | topic], publish, state) do
    case decode(topic, publish) do
      {key, :error} ->
        Logger.info("Invalid #{inspect(key)} value #{inspect(publish)} received")

      {key, value} ->
        Logger.debug("Got #{inspect(key)} #{inspect(value)}")
        Scrooge.Tesla.update_tesla_state(key, value)

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
