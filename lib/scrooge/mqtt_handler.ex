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
  def handle_message(_topic, message) do
    MqttPotion.Multiplexer.message(message.topic, message.payload)
    :ok
  end
end
