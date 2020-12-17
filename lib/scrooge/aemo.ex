defmodule Scrooge.Aemo do
  @moduledoc "Server to keep track of Aemo pricing information"

  use GenServer
  require Logger
  alias Scrooge.Aemo.Prices

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            aemo_state: map() | nil,
            scenes: list(GenServer.server()),
            timer: pid(),
            next_time: DateTime.t()
          }
    @enforce_keys [:aemo_state, :scenes, :timer, :next_time]
    defstruct [:aemo_state, :scenes, :timer, :next_time]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def poll do
    Logger.debug("Aemo.Poller: Got poll request")
    GenServer.call(__MODULE__, :poll, 30_000)
  end

  @spec register(GenServer.server()) :: :ok
  def register(pid) do
    GenServer.cast(__MODULE__, {:register, pid})
  end

  def get_aemo_state do
    GenServer.call(__MODULE__, :get_aemo_state)
  end

  def init(_opts) do
    state =
      %State{aemo_state: nil, scenes: [], timer: nil, next_time: nil}
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

    Logger.debug("Scrooge.Aemo: Sleeping #{milliseconds} for #{inspect(next_time)}.")
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

  def handle_call(:get_aemo_state, _from, state) do
    {:reply, state.aemo_state, state}
  end

  def handle_info(:timer, %State{next_time: next_time} = state) do
    now = DateTime.utc_now()
    earliest_time = next_time
    latest_time = Timex.shift(next_time, seconds: 10)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("Aemo.Poller: Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("Aemo.Poller: Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("Aemo.Poller: Timer received too late for #{next_time}.")

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

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp handle_poll(state) do
    headers = [
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{"timeScale" => ["30MIN"]})

    Mojito.request(
      method: :post,
      url: "https://aemo.com.au/aemo/apps/api/report/5MIN",
      headers: headers,
      body: body
    )
    |> handle_response(state)
  end

  defp handle_response({:error, error}, state) do
    Logger.error("Got error #{inspect(error)} talking to Aemo")
    state
  end

  defp handle_response({:ok, response}, state) do
    case response.status_code do
      200 ->
        data = Jason.decode!(response.body)
        data = data["5MIN"]
        data = add_prices(data)

        Enum.each(state.scenes, fn pid ->
          GenServer.cast(pid, {:update_aemo_state, data})
        end)

        %State{state | aemo_state: data}

      status ->
        Logger.error("Got error code #{status} talking to Aemo")
        state
    end
  end

  defp est_time(datetime_string) do
    {:ok, datetime} = NaiveDateTime.from_iso8601(datetime_string)
    {:ok, datetime} = DateTime.from_naive(datetime, "Etc/GMT-10")
    datetime
  end

  defp dt_to_utc_time(datetime) do
    {:ok, local_datetime} = DateTime.shift_zone(datetime, "Etc/GMT")
    local_datetime
  end

  defp dt_to_local_time(datetime) do
    {:ok, local_datetime} = DateTime.shift_zone(datetime, "Australia/Melbourne")
    local_datetime
  end

  defp add_prices(data) do
    meters = ["E1"]

    prices =
      data
      |> Enum.filter(fn entry -> entry["REGION"] == "VIC1" end)
      |> Enum.map(fn entry ->
        est_period = est_time(entry["SETTLEMENTDATE"])
        utc_period = dt_to_utc_time(est_period)

        # SETTLEMENTDATE is the end time for period, we want the start time
        utc_period = DateTime.add(utc_period, -(30 * 60))

        local_period = dt_to_local_time(utc_period)
        wholesale_price = entry["RRP"] / 1000 * 100

        carbon_neutral_offset = Prices.carbon_neutral_offset(local_period)
        environmental_certificate_cost = Prices.environmental_certificate_cost(local_period)
        market_charges = Prices.market_charges(local_period)
        price_protection_hedging = Prices.price_protection_hedging(local_period)
        loss_factor = Prices.loss_factor(local_period)

        prices =
          Enum.map(meters, fn meter ->
            network_tarif = Prices.network_tarif(meter, local_period)

            total_fixed =
              carbon_neutral_offset + environmental_certificate_cost + market_charges +
                price_protection_hedging + network_tarif

            total_wholesale = loss_factor * wholesale_price
            loss = total_wholesale - wholesale_price
            price = total_fixed + total_wholesale

            total_gst_price = price * 1.1
            gst = total_gst_price - price

            values = %{
              carbon_neutral_offset: carbon_neutral_offset,
              environmental_certificate_cost: environmental_certificate_cost,
              market_charges: market_charges,
              price_protection_hedging: price_protection_hedging,
              network_tarif: network_tarif,
              total_fixed: total_fixed,
              wholesale_price: wholesale_price,
              loss: loss,
              loss_factor: loss_factor,
              total_wholesale: total_wholesale,
              gst: gst,
              total_gst_price: total_gst_price
            }

            {meter, values}
          end)
          |> Enum.into(%{})

        entry
        |> Map.put("prices", prices)
        |> Map.put("period", utc_period)
      end)

    %{
      "variablePrices" => prices,
      "currentNEMtime" => DateTime.utc_now() |> dt_to_utc_time()
    }
  end
end
