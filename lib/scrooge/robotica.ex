defmodule Scrooge.Robotica do
  @moduledoc "Functions for talking to Robotica."

  require Logger

  @spec publish_raw(String.t(), String.t()) :: :ok | {:error, String.t()}
  def publish_raw(topic, data) do
    client_id = Scrooge.Application.get_tortoise_client_id()
    Tortoise.publish(client_id, topic, data, qos: 0)
  end

  @spec publish_json(String.t(), list() | map()) :: :ok | {:error, String.t()}
  def publish_json(topic, data) do
    with {:ok, data} <- Jason.encode(data),
         :ok <- publish_raw(topic, data) do
      :ok
    else
      {:error, msg} -> {:error, "Tortoise.publish got error '#{msg}'"}
    end
  end

  @spec publish_execute(map()) :: :ok | {:error, String.t()}
  def publish_execute(task) do
    topic = "execute"
    publish_json(topic, task)
  end

  @spec publish_message(String.t()) :: :ok | {:error, String.t()}
  def publish_message(message) do
    action = %{
      "locations" => ["Brian"],
      "action" => %{
        "message" => %{"text" => message}
      }
    }

    publish_execute(action)
  end
end
