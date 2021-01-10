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
            geofence: String.t() | nil,
            unlocked_time: DateTime.t() | nil
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
      :geofence,
      :unlocked_time
    ]
  end

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: TeslaState.t(),
            scenes: list(GenServer.server()),
            timer: pid(),
            next_time: DateTime.t(),
            active_conditions: MapSet.t()
          }
    defstruct tesla_state: %TeslaState{},
              scenes: [],
              timer: nil,
              next_time: nil,
              active_conditions: MapSet.new()
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

  def update_tesla_state(utc_time, key, value) do
    GenServer.cast(__MODULE__, {:update_tesla_state, utc_time, key, value})
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

  @spec robotica_test(
          atom(),
          MapSet.t(),
          boolean(),
          boolean(),
          String.t(),
          String.t()
        ) :: MapSet.t()
  defp robotica_test(id, active_conditions, ignore?, is_active?, new_msg, old_msg) do
    was_active = MapSet.member?(active_conditions, id)

    cond do
      ignore? ->
        active_conditions

      is_active? ->
        if robotica() do
          Scrooge.Robotica.publish_message(new_msg)
        end

        MapSet.put(active_conditions, id)

      was_active and not is_active? ->
        if robotica() do
          Scrooge.Robotica.publish_message(old_msg)
        end

        MapSet.delete(active_conditions, id)

      true ->
        active_conditions
    end
  end

  @spec unlocked_delta(DateTime.t(), TeslaState.t()) :: integer()
  defp unlocked_delta(utc_time, %TeslaState{} = tesla_state) do
    case tesla_state.unlocked_time do
      nil -> nil
      unlocked_time -> Timex.diff(utc_time, unlocked_time, :seconds)
    end
  end

  @spec check_insecure(DateTime.t(), TeslaState.t()) :: boolean
  defp check_insecure(utc_time, tesla_state) do
    unlocked_delta = unlocked_delta(utc_time, tesla_state)
    unlocked_delta != nil and unlocked_delta > 300 and tesla_state.is_user_present == false
  end

  @spec robotica_check_all(MapSet.t(), atom(), any(), any(), DateTime.t(), TeslaState.t()) ::
          MapSet.t()
  defp robotica_check_all(
         active_conditions,
         key,
         old_value,
         new_value,
         utc_time,
         %TeslaState{} = tesla_state
       ) do
    case key do
      :geofence ->
        robotica_test(
          key,
          active_conditions,
          false,
          new_value != nil,
          "The tesla has arrived at #{new_value}.",
          "The tesla has departed from #{old_value}."
        )

      :plugged_in ->
        robotica_test(
          key,
          active_conditions,
          old_value == nil,
          new_value == true,
          "The tesla has been plugged in.",
          "The tesla has been disconnected."
        )

      :locked ->
        robotica_test(
          :insecure,
          active_conditions,
          false,
          check_insecure(utc_time, tesla_state),
          "The tesla is feeling insecure (unlocked).",
          "The tesla is feeling secure (locked)."
        )

      :is_user_present ->
        robotica_test(
          :insecure,
          active_conditions,
          false,
          check_insecure(utc_time, tesla_state),
          "The tesla is feeling insecure (no driver).",
          "The tesla is feeling secure (driver returned)."
        )

      _ ->
        active_conditions
    end
  end

  defp check_unlocked_time(%TeslaState{} = tesla_state, :locked, utc_time, old_value, new_value) do
    cond do
      old_value == true and new_value == false ->
        %TeslaState{tesla_state | unlocked_time: utc_time}

      tesla_state.unlocked_time == nil and new_value == false ->
        %TeslaState{tesla_state | unlocked_time: utc_time}

      new_value == true ->
        %TeslaState{tesla_state | unlocked_time: nil}

      true ->
        tesla_state
    end
  end

  defp check_unlocked_time(%TeslaState{} = tesla_state, _, _utc_time, _old_value, _new_value),
    do: tesla_state

  defp is_after_time(utc_now, time) do
    threshold_time =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Timex.set(time: time)
      |> Timex.Timezone.convert("Etc/UTC")

    Timex.compare(utc_now, threshold_time) >= 0
  end

  defp handle_poll(%State{} = state) do
    if robotica() do
      tesla_state = state.tesla_state
      active_conditions = state.active_conditions
      begin_charge_time = ~T[20:00:00]
      utc_now = DateTime.utc_now()

      at_home = tesla_state.geofence == "home"

      active_conditions =
        if is_after_time(utc_now, begin_charge_time) and at_home do
          MapSet.put(active_conditions, :plug_in_required)
        else
          MapSet.delete(active_conditions, :plug_in_required)
        end

      active_conditions =
        if check_insecure(utc_now, tesla_state) do
          MapSet.put(active_conditions, :insecure)
        else
          MapSet.delete(active_conditions, :insecure)
        end

      if MapSet.member?(active_conditions, :plug_in_required) and not state.plugged_in do
        Scrooge.Robotica.publish_message("Plug in the Tesla")
      end

      if MapSet.member?(active_conditions, :insecure) do
        Scrooge.Robotica.publish_message("The tesla is insecure, please lock the tesla")
      end

      %State{state | active_conditions: active_conditions}
    end
  end

  def handle_cast({:update_tesla_state, utc_time, key, new_value}, %State{} = state) do
    old_state = state.tesla_state
    old_value = Map.get(old_state, key)

    new_state =
      Map.put(state.tesla_state, key, new_value)
      |> check_unlocked_time(key, utc_time, old_value, new_value)

    state =
      if old_value != new_value do
        active_conditions =
          robotica_check_all(
            state.active_conditions,
            key,
            old_value,
            new_value,
            utc_time,
            new_state
          )

        %State{state | active_conditions: active_conditions}
      else
        state
      end

    Enum.each(state.scenes, fn pid ->
      GenServer.cast(pid, {:update_tesla_state, state.active_conditions, new_state})
    end)

    {:noreply, %State{state | tesla_state: new_state}}
  end

  def handle_cast({:register, pid}, %State{} = state) do
    Process.monitor(pid)
    state = %State{state | scenes: [pid | state.scenes]}
    Logger.info("register web scene #{inspect(pid)} #{inspect(state.scenes)}")
    {:noreply, state}
  end

  def handle_call(:get_tesla_state, _from, %State{} = state) do
    {:reply, {state.active_conditions, state.tesla_state}, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
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
