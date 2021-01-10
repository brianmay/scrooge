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

  defmodule Conditions do
    @moduledoc false
    @type t :: %__MODULE__{
            geofence: String.t() | nil,
            plugged_in: boolean(),
            insecure: boolean(),
            plug_in_required: boolean()
          }
    defstruct geofence: nil,
              plugged_in: false,
              insecure: false,
              plug_in_required: false
  end

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: TeslaState.t(),
            scenes: list(GenServer.server()),
            timer: pid(),
            next_time: DateTime.t(),
            active_conditions: Conditions.t()
          }
    defstruct tesla_state: %TeslaState{},
              scenes: [],
              timer: nil,
              next_time: nil,
              active_conditions: %Conditions{}
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

  @spec unlocked_delta(DateTime.t(), TeslaState.t()) :: integer()
  defp unlocked_delta(utc_time, %TeslaState{} = tesla_state) do
    case tesla_state.unlocked_time do
      nil -> nil
      unlocked_time -> Timex.diff(utc_time, unlocked_time, :seconds)
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

  @spec test_insecure(DateTime.t(), TeslaState.t()) :: boolean
  defp test_insecure(utc_time, tesla_state) do
    unlocked_delta = unlocked_delta(utc_time, tesla_state)
    unlocked = unlocked_delta != nil and unlocked_delta > 300
    windows_open = tesla_state.windows_open == true and tesla_state.locked == true
    (unlocked or windows_open) and tesla_state.is_user_present == false
  end

  @spec test_plug_in_required(DateTime.t(), TeslaState.t()) :: boolean
  defp test_plug_in_required(utc_time, tesla_state) do
    at_home = tesla_state.geofence == "home"
    begin_charge_time = ~T[20:00:00]
    is_after_time(utc_time, begin_charge_time) and at_home and not tesla_state.plugged_in
  end

  @spec get_conditions(DateTime.t(), TeslaState.t()) :: Conditions.t()
  defp get_conditions(utc_time, %TeslaState{} = tesla_state) do
    %Conditions{
      geofence: tesla_state.geofence,
      plugged_in: tesla_state.plugged_in == true,
      insecure: test_insecure(utc_time, tesla_state),
      plug_in_required: test_plug_in_required(utc_time, tesla_state)
    }
  end

  @spec check_geofence(String.t() | nil, String.t() | nil) :: :ok
  def check_geofence(old, new) do
    cond do
      old != new and new != nil ->
        Scrooge.Robotica.publish_message("The tesla arrived at #{new}.")

      old != nil and new == nil ->
        Scrooge.Robotica.publish_message("The tesla departed from #{old}.")

      true ->
        nil
    end
  end

  @spec check_plugged_in(boolean(), boolean()) :: :ok
  defp check_plugged_in(old, new) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The tesla is plugged in.")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The tesla is disconnected.")

      true ->
        nil
    end
  end

  @spec check_insecure(boolean(), boolean()) :: :ok
  defp check_insecure(old, new) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The tesla is feeling insecure")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The tesla is feeling secure")

      true ->
        nil
    end
  end

  @spec check_plug_in_required(boolean(), boolean()) :: :ok
  defp check_plug_in_required(old, new) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The tesla requires plugging in")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The tesla no longer requires plugging in")

      true ->
        nil
    end
  end

  @spec check_conditions(Conditions.t(), Conditions.t()) :: :ok
  defp check_conditions(old, new) do
    check_geofence(old.geofence, new.geofence)
    check_plugged_in(old.plugged_in, new.plugged_in)
    check_insecure(old.insecure, new.insecure)
    check_plug_in_required(old.insecure, new.insecure)
    :ok
  end

  @spec robotica_check_all(DateTime.t(), TeslaState.t(), Conditions.t()) :: Conditions.t()
  defp robotica_check_all(
         utc_time,
         %TeslaState{} = tesla_state,
         old_conditions
       ) do
    new_conditions = get_conditions(utc_time, tesla_state)

    if robotica() do
      :ok = check_conditions(old_conditions, new_conditions)
    end

    new_conditions
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

  defp handle_poll(%State{} = state) do
    utc_now = DateTime.utc_now()

    tesla_state = state.tesla_state
    old_conditions = state.active_conditions

    new_conditions = get_conditions(utc_now, tesla_state)

    if robotica() do
      :ok = check_conditions(old_conditions, new_conditions)
    end

    %State{state | active_conditions: new_conditions}
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
            utc_time,
            new_state,
            state.active_conditions
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
