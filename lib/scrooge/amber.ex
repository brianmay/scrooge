defmodule Scrooge.Amber do
  @moduledoc false

  use GenServer
  require Logger
  alias Scrooge.Amber.Prices

  defmodule State do
    @type t :: %__MODULE__{
            amber_state: map() | nil,
            scenes: list(GenServer.server()),
            timer: pid(),
            next_time: DateTime.t()
          }
    @enforce_keys [:amber_state, :scenes, :timer, :next_time]
    defstruct [:amber_state, :scenes, :timer, :next_time]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def poll() do
    Logger.debug("TeNerves.Poller: Got poll request")
    GenServer.call(__MODULE__, :poll, 30000)
  end

  @spec register(GenServer.server()) :: nil
  def register(pid) do
    GenServer.cast(__MODULE__, {:register, pid})
  end

  def get_amber_state() do
    GenServer.call(__MODULE__, :get_amber_state)
  end

  def init(_opts) do
    state =
      %State{amber_state: nil, scenes: [], timer: nil, next_time: nil}
      |> set_timer()

    {:ok, state}
  end

  def get_next_time(now) do
    interval = 300
    Scrooge.Times.round_time(now, interval, 1)
  end

  defp maximum(v, max) when v > max, do: max
  defp maximum(v, _max), do: v

  defp minimum(v, max) when v < max, do: max
  defp minimum(v, _max), do: v

  defp set_timer(%State{next_time: next_time} = state) do
    now = DateTime.utc_now()

    next_time =
      case next_time do
        nil -> get_next_time(now)
        next_time -> next_time
      end

    milliseconds = DateTime.diff(next_time, now, :millisecond)
    milliseconds = maximum(milliseconds, 60 * 1000)
    milliseconds = minimum(milliseconds, 0)

    Logger.debug("Scrooge.Amber: Sleeping #{milliseconds} for #{inspect(next_time)}.")
    timer = Process.send_after(self(), :timer, milliseconds)

    %State{
      state
      | timer: timer,
        next_time: next_time
    }
  end

  def handle_cast({:register, pid}, state) do
    Process.monitor(pid)
    state = %State{state | scenes: [pid | state.scenes]}
    Logger.info("register web scene #{inspect(pid)} #{inspect(state.scenes)}")
    {:noreply, state}
  end

  def handle_call(:poll, _from, state) do
    new_state = handle_poll(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_amber_state, _from, state) do
    {:reply, state.amber_state, state}
  end

  def handle_info(:timer, %State{next_time: next_time} = state) do
    now = DateTime.utc_now()
    earliest_time = next_time
    latest_time = Timex.shift(next_time, seconds: 10)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("TeNerves.Poller: Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("TeNerves.Poller: Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("TeNerves.Poller: Timer received too late for #{next_time}.")

          state
          |> Map.put(:next_time, nil)
          |> set_timer()
      end

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = %State{state | scenes: List.delete(state.scenes, pid)}
    Logger.info("unregister web scene #{inspect(pid)} #{inspect(state.scenes)}")
    {:noreply, state}
  end

  defp handle_poll(state) do
    headers = [
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{"postcode" => "3787"})

    {:ok, response} =
      Mojito.request(
        method: :post,
        url: "https://api.amberelectric.com.au/prices/listprices",
        headers: headers,
        body: body
      )

    case response.status_code do
      200 ->
        data = Jason.decode!(response.body)
        data = data["data"]
        data = add_prices(data)

        Enum.each(state.scenes, fn pid ->
          GenServer.cast(pid, {:update_amber_state, data})
        end)

        %State{state | amber_state: data}

      status ->
        Logger.error("Got error #{status} talking to Amber")
        state
    end
  end

  defp to_float(str) do
    {value, ""} = Float.parse(str)
    value
  end

  defp utc_time(datetime_string) do
    {:ok, datetime} = NaiveDateTime.from_iso8601(datetime_string)
    {:ok, datetime} = DateTime.from_naive(datetime, "Etc/GMT-10")
    datetime
  end

  defp utc_to_local_time(datetime) do
    {:ok, local_datetime} = DateTime.shift_zone(datetime, "Australia/Melbourne")
    local_datetime
  end

  defp add_prices(data) do
    meter_prices =
      Enum.map(data["staticPrices"], fn {meter, value} ->
        total_fixed_price = to_float(value["totalfixedKWHPrice"])
        loss_factor = to_float(value["lossFactor"])
        {meter, total_fixed_price, loss_factor}
      end)

    prices =
      Enum.map(data["variablePricesAndRenewables"], fn entry ->
        utc_period = utc_time(entry["period"])
        local_period = utc_to_local_time(utc_period)
        wholesale_price = to_float(entry["wholesaleKWHPrice"])

        loss_factor = Prices.get_loss_factor(local_period)
        green_tarif = Prices.get_green_tarif(local_period)
        market_environment_tarif = Prices.get_market_environment_tarif(local_period)

        prices =
          Enum.map(meter_prices, fn {meter, _total_fixed_price, _loss_factor} ->
            network_tarif = Prices.get_network_tarif(meter, local_period)
            total_fixed_price = network_tarif + green_tarif + market_environment_tarif

            IO.puts(
              "#{inspect(local_period)} #{network_tarif} #{green_tarif} #{
                market_environment_tarif
              }"
            )

            price = total_fixed_price + loss_factor * wholesale_price

            values = %{
              network_tarif: network_tarif,
              green_tarif: green_tarif,
              market_environment_tarif: market_environment_tarif,
              loss_factor: loss_factor,
              wholesale_price: wholesale_price,
              price: price
            }

            {meter, values}
          end)
          |> Enum.into(%{})

        entry = Map.put(entry, "prices", prices)

        renewables = to_float(entry["renewablesPercentage"]) * 100
        %{entry | "period" => utc_period, "renewablesPercentage" => renewables}
      end)

    %{
      data
      | "variablePricesAndRenewables" => prices,
        "currentNEMtime" => utc_time(data["currentNEMtime"])
    }
  end
end
