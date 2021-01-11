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
            battery_level: integer() | nil,
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
      :battery_level,
      :unlocked_time
    ]
  end

  defmodule Conditions do
    @moduledoc false
    @type t :: map()
  end

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: TeslaState.t(),
            scenes: list(GenServer.server()),
            timer: reference() | nil,
            next_time: DateTime.t() | nil,
            silence_alerts: boolean(),
            alert_time: DateTime.t() | nil,
            active_conditions: Conditions.t()
          }
    defstruct tesla_state: %TeslaState{},
              scenes: [],
              timer: nil,
              next_time: nil,
              silence_alerts: true,
              alert_time: nil,
              active_conditions: %{}
  end

  defmodule Rule do
    @moduledoc false
    @type t :: %__MODULE__{
            id: atom(),
            test: (DateTime.t(), TeslaState.t() -> boolean()),
            data: (DateTime.t(), TeslaState.t() -> any()),
            on_msg: (any() -> String.t()) | nil,
            alert_msg: (any() -> String.t()) | nil,
            off_msg: (any() -> String.t()) | nil
          }
    @enforce_keys [:id, :test, :data, :on_msg, :alert_msg, :off_msg]
    defstruct [:id, :test, :data, :on_msg, :alert_msg, :off_msg]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec init(map()) :: {:ok, State.t()}
  def init(_opts) do
    # Allow state to stabilize after start
    Process.send_after(self(), :desilence, 1000)
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

  @spec get_next_time(DateTime.t(), integer) :: DateTime.t()
  def get_next_time(now, interval) do
    Scrooge.Times.round_time(now, interval, 1)
  end

  @spec maximum(integer(), integer()) :: integer()
  defp maximum(v, max) when v > max, do: max
  defp maximum(v, _max), do: v

  @spec minimum(integer(), integer()) :: integer()
  defp minimum(v, max) when v < max, do: max
  defp minimum(v, _max), do: v

  @spec set_timer(State.t()) :: State.t()
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
      "Tesla.Poller: Sleeping #{milliseconds} for #{inspect(next_time)} / #{inspect(alert_time)}."
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

  @spec is_after_time(DateTime.t(), Time.t()) :: boolean()
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
    unlocked and tesla_state.is_user_present == false
  end

  @spec test_plug_in_required(DateTime.t(), TeslaState.t()) :: boolean
  defp test_plug_in_required(utc_time, tesla_state) do
    at_home = tesla_state.geofence == "Home"
    normal_charge_time = ~T[20:00:00]
    urgent_charge_time = ~T[08:00:00]

    battery_normal = tesla_state.battery_level != nil and tesla_state.battery_level <= 80
    battery_urgent = tesla_state.battery_level != nil and tesla_state.battery_level <= 50
    battery_urgent = battery_urgent or tesla_state.battery_level == nil

    normal = is_after_time(utc_time, normal_charge_time) and battery_normal
    urgent = is_after_time(utc_time, urgent_charge_time) and battery_urgent
    at_home and tesla_state.plugged_in == false and (normal or urgent)
  end

  @spec get_rules() :: list(Rule.t())
  defp get_rules,
    do: [
      %Rule{
        id: :geofence,
        test: fn _, tesla_state -> tesla_state.geofence != nil end,
        data: fn _, tesla_state -> tesla_state.geofence end,
        on_msg: fn data -> "The Tesla arrived at #{data}" end,
        alert_msg: nil,
        off_msg: fn data -> "The Tesla departed from #{data}." end
      },
      %Rule{
        id: :plugged_in,
        test: fn _, tesla_state -> tesla_state.plugged_in == true end,
        data: fn _, _ -> nil end,
        on_msg: fn _ -> "The Tesla is plugged in" end,
        alert_msg: nil,
        off_msg: fn _ -> "The Tesla is disconnected." end
      },
      %Rule{
        id: :insecure,
        test: fn utc_time, tesla_state -> test_insecure(utc_time, tesla_state) end,
        data: fn _, _ -> nil end,
        on_msg: fn _ -> "The Tesla is feeling insecure." end,
        alert_msg: fn _ -> "Lock the Tesla." end,
        off_msg: fn _ -> "The Tesla is not insecure." end
      },
      %Rule{
        id: :plug_in_required,
        test: fn utc_time, tesla_state -> test_plug_in_required(utc_time, tesla_state) end,
        data: fn _, _ -> nil end,
        on_msg: fn _ -> "The Tesla requires plugging in." end,
        alert_msg: fn _ -> "Plug in the Tesla." end,
        off_msg: fn _ -> "The Tesla no longer requires plugging in." end
      }
    ]

  @spec get_conditions(DateTime.t(), TeslaState.t()) :: Conditions.t()
  defp get_conditions(utc_time, %TeslaState{} = tesla_state) do
    Enum.reduce(get_rules(), %{}, fn rule, conditions ->
      test = rule.test.(utc_time, tesla_state)
      data = rule.data.(utc_time, tesla_state)
      Map.put(conditions, rule.id, {test, data})
    end)
  end

  @spec publish_msg((TeslaState.t() -> String.t()) | nil, any()) :: :ok
  defp publish_msg(nil, _), do: :ok

  defp publish_msg(msg, data) do
    if msg != nil and robotica() do
      str = msg.(data)
      Scrooge.Robotica.publish_message(str)
    end
  end

  @spec check_rule(Rule.t(), {boolean(), any()}, {boolean(), any()}, boolean()) :: :ok
  def check_rule(rule, {old_test, old_data}, {new_test, new_data}, alert) do
    cond do
      old_test == false and new_test == true -> publish_msg(rule.on_msg, new_data)
      alert == true and new_test == true -> publish_msg(rule.alert_msg, new_data)
      old_test == true and new_test == false -> publish_msg(rule.off_msg, old_data)
      true -> :ok
    end

    :ok
  end

  @spec check_conditions(
          Conditions.t(),
          Conditions.t(),
          boolean()
        ) :: :ok
  defp check_conditions(
         old_conditions,
         new_conditions,
         alert
       ) do
    Enum.each(get_rules(), fn rule ->
      old_value = Map.fetch!(old_conditions, rule.id)
      new_value = Map.fetch!(new_conditions, rule.id)
      check_rule(rule, old_value, new_value, alert)
    end)

    :ok
  end

  @spec robotica_check_all(
          DateTime.t(),
          Conditions.t(),
          TeslaState.t(),
          keyword()
        ) :: Conditions.t()
  defp robotica_check_all(
         utc_time,
         old_conditions,
         %TeslaState{} = new_state,
         opts
       ) do
    new_conditions = get_conditions(utc_time, new_state)

    if Keyword.get(opts, :silence_alerts, false) == false do
      :ok = check_conditions(old_conditions, new_conditions, false)
    end

    new_conditions
  end

  @spec check_unlocked_time(TeslaState.t(), atom(), DateTime.t(), any(), any()) :: TeslaState.t()
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

    if state.silence_alerts == false do
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
            state.active_conditions,
            new_state,
            silence_alerts: state.silence_alerts
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

  def handle_info(:desilence, %State{} = state) do
    # Allow state to stabilize after start
    Logger.info("desilencing alerts")
    {:noreply, %State{state | silence_alerts: false}}
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
