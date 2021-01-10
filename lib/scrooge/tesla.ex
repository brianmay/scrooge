defmodule Scrooge.Tesla do
  @moduledoc "A server that keeps track of the latest Tesla information"

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
            next_time: DateTime.t() | nil,
            alert_time: DateTime.t() | nil,
            active_conditions: Conditions.t()
          }
    defstruct tesla_state: %TeslaState{},
              scenes: [],
              timer: nil,
              next_time: nil,
              alert_time: nil,
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

  def get_next_time(now, interval) do
    Scrooge.Times.round_time(now, interval, 1)
  end

  defp maximum(v, max) when v > max, do: max
  defp maximum(v, _max), do: v

  defp minimum(v, max) when v < max, do: max
  defp minimum(v, _max), do: v

  defp set_timer(%State{next_time: next_time, alert_time: alert_time} = state) do
    now = DateTime.utc_now()

    next_time =
      case next_time do
        nil -> get_next_time(now, 60)
        next_time -> next_time
      end

    alert_time =
      case alert_time do
        nil -> get_next_time(now, 600)
        alert_time -> alert_time
      end

    milliseconds = DateTime.diff(next_time, now, :millisecond)
    milliseconds = maximum(milliseconds, 60 * 1000)
    milliseconds = minimum(milliseconds, 0)

    Logger.debug(
      "Scrooge.Tesla: Sleeping #{milliseconds} for #{inspect(next_time)} / #{inspect(alert_time)}."
    )

    timer = Process.send_after(self(), :timer, milliseconds)

    %State{
      state
      | timer: timer,
        next_time: next_time,
        alert_time: alert_time
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
    at_home = tesla_state.geofence == "Home"
    begin_charge_time = ~T[20:00:00]
    is_after_time(utc_time, begin_charge_time) and at_home and tesla_state.plugged_in == false
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

  @spec check_geofence(String.t() | nil, String.t() | nil, boolean()) :: :ok
  def check_geofence(old, new, _alert) do
    cond do
      old != new and new != nil ->
        Scrooge.Robotica.publish_message("The Tesla arrived at #{new}.")

      old != nil and new == nil ->
        Scrooge.Robotica.publish_message("The Tesla departed from #{old}.")

      true ->
        nil
    end
  end

  @spec check_plugged_in(boolean(), boolean(), boolean()) :: :ok
  defp check_plugged_in(old, new, _alert) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The Tesla is plugged in.")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The Tesla is disconnected.")

      true ->
        nil
    end
  end

  @spec check_insecure(boolean(), boolean(), boolean()) :: :ok
  defp check_insecure(old, new, alert) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The Tesla is feeling insecure.")

      alert == true and new == true ->
        Scrooge.Robotica.publish_message("Lock Tesla.")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The Tesla is feeling secure.")

      true ->
        nil
    end
  end

  @spec check_plug_in_required(boolean(), boolean(), boolean()) :: :ok
  defp check_plug_in_required(old, new, alert) do
    cond do
      old == false and new == true ->
        Scrooge.Robotica.publish_message("The Tesla requires plugging in.")

      alert == true and new == true ->
        Scrooge.Robotica.publish_message("Plug in Tesla.")

      old == true and new == false ->
        Scrooge.Robotica.publish_message("The Tesla no longer requires plugging in.")

      true ->
        nil
    end
  end

  @spec check_conditions(Conditions.t(), Conditions.t(), boolean()) :: :ok
  defp check_conditions(old, new, alert) do
    check_geofence(old.geofence, new.geofence, alert)
    check_plugged_in(old.plugged_in, new.plugged_in, alert)
    check_insecure(old.insecure, new.insecure, alert)
    check_plug_in_required(old.plug_in_required, new.plug_in_required, alert)
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
      :ok = check_conditions(old_conditions, new_conditions, false)
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

  @spec handle_poll(State.t(), boolean()) :: State.t()
  defp handle_poll(%State{} = state, alert) do
    utc_now = DateTime.utc_now()

    tesla_state = state.tesla_state
    old_conditions = state.active_conditions

    new_conditions = get_conditions(utc_now, tesla_state)

    if robotica() do
      :ok = check_conditions(old_conditions, new_conditions, alert)
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

  @spec check_alert_time(State.t(), DateTime.t()) :: boolean()
  defp check_alert_time(%State{alert_time: alert_time}, utc_now) do
    not Timex.before?(utc_now, alert_time)
  end

  @spec maybe_reset_alert_time(State.t(), boolean()) :: State.t()
  defp maybe_reset_alert_time(%State{} = state, false), do: state
  defp maybe_reset_alert_time(%State{} = state, true), do: %State{state | alert_time: nil}

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
          alert = check_alert_time(state, now)
          Logger.debug("Tesla.Poller: Timer received on time for #{next_time} is alert #{alert}.")

          state
          |> handle_poll(alert)
          |> Map.put(:next_time, nil)
          |> maybe_reset_alert_time(alert)
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
