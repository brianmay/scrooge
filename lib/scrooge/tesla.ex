defmodule Scrooge.Tesla do
  @moduledoc "A server that keeps track of the latest tesla information"

  use GenServer
  require Logger

  defp robotica, do: Application.get_env(:scrooge, :robotica)

  defmodule TeslaState do
    @moduledoc false
    @type t :: %__MODULE__{
            latitude: float() | nil,
            longitude: float() | nil,
            heading: integer() | nil,
            speed: integer() | nil,
            since: DateTime.t() | nil,
            doors_open: boolean() | nil,
            trunk_open: boolean() | nil,
            frunk_open: boolean() | nil,
            windows_open: boolean() | nil,
            plugged_in: boolean() | nil,
            locked: boolean() | nil,
            is_user_present: boolean() | nil,
            geofence: String.t() | nil | :none
          }
    defstruct [
      :latitude,
      :longitude,
      :heading,
      :speed,
      :since,
      :doors_open,
      :trunk_open,
      :frunk_open,
      :windows_open,
      :plugged_in,
      :locked,
      :is_user_present,
      :geofence
    ]
  end

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: TeslaState.t(),
            scenes: list(GenServer.server()),
            timer: pid(),
            next_time: DateTime.t()
          }
    defstruct tesla_state: %TeslaState{}, scenes: [], timer: nil, next_time: nil
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %State{} |> set_timer()}
  end

  def config_schema do
    %{}
  end

  @spec register(GenServer.server()) :: :ok
  def register(pid) do
    GenServer.cast(__MODULE__, {:register, pid})
  end

  def update_tesla_state(key, value) do
    GenServer.cast(__MODULE__, {:update_tesla_state, key, value})
  end

  def get_tesla_state do
    GenServer.call(__MODULE__, :get_tesla_state)
  end

  def get_next_time(now) do
    interval = 600
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

    Logger.debug("Scrooge.Tesla: Sleeping #{milliseconds} for #{inspect(next_time)}.")
    timer = Process.send_after(self(), :timer, milliseconds)

    %State{
      state
      | timer: timer,
        next_time: next_time
    }
  end

  defp robotica_test(old_value, new_value, test, new_msg, old_msg) do
    cond do
      old_value == nil ->
        :ok

      new_value == nil ->
        :ok

      test.(new_value) ->
        Scrooge.Robotica.publish_message(new_msg)

      test.(old_value) ->
        Scrooge.Robotica.publish_message(old_msg)

      true ->
        :ok
    end
  end

  defp robotica(key, old_value, new_value) do
    case key do
      :geofence ->
        robotica_test(
          old_value,
          new_value,
          fn value -> value != :none end,
          "The tesla has arrived at #{new_value}.",
          "The tesla has departed from #{old_value}."
        )

      :plugged_in ->
        robotica_test(
          old_value,
          new_value,
          fn value -> value == true end,
          "The tesla has been plugged in.",
          "The tesla has been disconnected."
        )

      :locked ->
        robotica_test(
          old_value,
          new_value,
          fn value -> value == true end,
          "The tesla has been locked.",
          "The tesla has been unlocked."
        )

      :is_user_present ->
        robotica_test(
          old_value,
          new_value,
          fn value -> value == true end,
          "The tesla driver has returned.",
          "The tesla driver has disappeared."
        )

      _ ->
        :ok
    end
  end

  defp is_after_time(utc_now, time) do
    threshold_time =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Timex.set(time: time)
      |> Timex.Timezone.convert("Etc/UTC")

    Timex.compare(utc_now, threshold_time) >= 0
  end

  defp handle_poll(state) do
    if robotica() do
      tesla_state = state.tesla_state
      begin_charge_time = ~T[20:00:00]
      utc_now = DateTime.utc_now()

      at_home = tesla_state.geofence == "home"

      if is_after_time(utc_now, begin_charge_time) and not tesla_state.plugged_in and at_home do
        Scrooge.Robotica.publish_message("Plug in Tesla")
      end
    end

    state
  end

  def handle_cast({:update_tesla_state, key, new_value}, state) do
    old_state = state.tesla_state
    old_value = Map.get(old_state, key)

    new_state = Map.put(state.tesla_state, key, new_value)

    if robotica() and old_value != new_value do
      robotica(key, old_value, new_value)
    end

    Enum.each(state.scenes, fn pid ->
      GenServer.cast(pid, {:update_tesla_state, new_state})
    end)

    {:noreply, %{state | tesla_state: new_state}}
  end

  def handle_cast({:register, pid}, state) do
    Process.monitor(pid)
    state = %State{state | scenes: [pid | state.scenes]}
    Logger.info("register web scene #{inspect(pid)} #{inspect(state.scenes)}")
    {:noreply, state}
  end

  def handle_call(:get_tesla_state, _from, state) do
    {:reply, state.tesla_state, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = %State{state | scenes: List.delete(state.scenes, pid)}
    Logger.info("unregister web scene #{inspect(pid)} #{inspect(state.scenes)}")
    {:noreply, state}
  end

  def handle_info(:timer, %State{next_time: next_time} = state) do
    now = DateTime.utc_now()
    earliest_time = next_time
    latest_time = Timex.shift(next_time, seconds: 10)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("Tesla.Poller: Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("Tesla.Poller: Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("Tesla.Poller: Timer received too late for #{next_time}.")

          state
          |> Map.put(:next_time, nil)
          |> set_timer()
      end

    {:noreply, new_state}
  end
end
