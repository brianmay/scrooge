defmodule Scrooge.Amber.Worker do
  @moduledoc """
  Get Amber information
  """
  use Task
  alias Scrooge.PubSub
  require Logger

  def start_link({start_date, end_date}) do
    Task.start_link(__MODULE__, :run, [start_date, end_date])
  end

  def run(start_date, end_date) do
    get_prices(start_date, end_date) |> notify_subscribers_prices()
    get_usage(start_date, end_date) |> notify_subscribers_usage()
    notify_subscribers_done()
  end

  defp get_prices(start_date, end_date, tries \\ 3) do
    token = Application.get_env(:scrooge, :amber_token)
    site_id = Application.get_env(:scrooge, :amber_site_id)

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{token}"}
    ]

    params = %{
      "startDate" => Date.to_string(start_date),
      "endDate" => Date.to_string(end_date)
    }

    url = "https://api.amber.com.au/v1/sites/#{site_id}/prices?" <> URI.encode_query(params)

    Mojito.request(
      method: :get,
      url: url,
      headers: headers
    )
    |> handle_prices_response(start_date, end_date, tries)
  end

  defp handle_prices_response(
         {:error, %Mojito.Error{reason: :timeout}},
         start_date,
         end_date,
         tries
       )
       when tries > 0 do
    Logger.warn("Got timeout talking to Amber (tries left: #{tries})")
    get_prices(start_date, end_date, tries - 1)
  end

  defp handle_prices_response({:error, error}, _, _, _) do
    Logger.error("Got error #{inspect(error)} talking to Amber")
    {:error, "Got error #{inspect(error)} talking to Amber"}
  end

  defp handle_prices_response({:ok, response}, _, _, _) do
    case response.status_code do
      200 ->
        {:ok, Jason.decode!(response.body)}

      status ->
        Logger.error("Got error code #{status} talking to Amber #{inspect(response.body)}")
        {:error, "Got error code #{status} talking to Amber #{inspect(response.body)}"}
    end
  end

  defp get_usage(start_date, end_date, tries \\ 3) do
    token = Application.get_env(:scrooge, :amber_token)
    site_id = Application.get_env(:scrooge, :amber_site_id)

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{token}"}
    ]

    params = %{
      "startDate" => Date.to_string(start_date),
      "endDate" => Date.to_string(end_date)
    }

    url = "https://api.amber.com.au/v1/sites/#{site_id}/usage?" <> URI.encode_query(params)

    Mojito.request(
      method: :get,
      url: url,
      headers: headers
    )
    |> handle_usage_response(start_date, end_date, tries)
  end

  defp handle_usage_response(
         {:error, %Mojito.Error{reason: :timeout}},
         start_date,
         end_date,
         tries
       )
       when tries > 0 do
    Logger.warn("Got timeout talking to Amber (tries left: #{tries})")
    get_usage(start_date, end_date, tries - 1)
  end

  defp handle_usage_response({:error, error}, _, _, _) do
    Logger.error("Got error #{inspect(error)} talking to Amber")
    {:error, "Got error #{inspect(error)} talking to Amber"}
  end

  defp handle_usage_response({:ok, response}, _, _, _) do
    case response.status_code do
      200 ->
        {:ok, Jason.decode!(response.body)}

      status ->
        Logger.error("Got error code #{status} talking to Amber #{inspect(response.body)}")
        {:error, "Got error code #{status} talking to Amber #{inspect(response.body)}"}
    end
  end

  @topic inspect(__MODULE__)

  defp notify_subscribers_prices(prices) do
    Phoenix.PubSub.broadcast(PubSub, @topic, {:prices, prices})
  end

  defp notify_subscribers_usage(usage) do
    Phoenix.PubSub.broadcast(PubSub, @topic, {:usage, usage})
  end

  defp notify_subscribers_done do
    Phoenix.PubSub.broadcast(PubSub, @topic, {:done})
  end

  def subscribe do
    Phoenix.PubSub.subscribe(PubSub, @topic)
  end
end
