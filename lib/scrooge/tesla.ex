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
            geofence: String.t() | nil
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
      :geofence
    ]
  end

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: TeslaState.t(),
            scenes: list(GenServer.server())
          }
    defstruct tesla_state: %TeslaState{}, scenes: []
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %State{}}
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

  defp robotica(key, old_value, new_value, _new_state) do
    case key do
      :geofence ->
        if old_value != new_value do
          cond do
            not is_nil(new_value) ->
              Scrooge.Robotica.publish_message("The tesla has arrived at #{new_value}.")

            not is_nil(old_value) ->
              Scrooge.Robotica.publish_message("The tesla has departed from #{old_value}.")
          end
        end

      :plugged_in ->
        if old_value != new_value do
          cond do
            new_value == true ->
              Scrooge.Robotica.publish_message("The tesla has been plugged in.")

            old_value == true ->
              Scrooge.Robotica.publish_message("The tesla has been disconnected.")
          end
        end

      _ ->
        nil
    end
  end

  def handle_cast({:update_tesla_state, key, new_value}, state) do
    old_state = state.tesla_state
    old_value = Map.get(old_state, key)

    new_state = Map.put(state.tesla_state, key, new_value)

    if robotica() and not is_nil(old_value) do
      robotica(key, old_value, new_value, new_state)
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
end
