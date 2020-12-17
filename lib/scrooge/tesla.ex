defmodule Scrooge.Tesla do
  @moduledoc "A server that keeps track of the latest tesla information"

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            tesla_state: map() | nil,
            scenes: list(GenServer.server())
          }
    defstruct tesla_state: nil, scenes: []
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

  def update_tesla_state(tesla_state) do
    GenServer.cast(__MODULE__, {:update_tesla_state, tesla_state})
  end

  def get_tesla_state do
    GenServer.call(__MODULE__, :get_tesla_state)
  end

  def handle_cast({:update_tesla_state, tesla_state}, state) do
    Enum.each(state.scenes, fn pid ->
      GenServer.cast(pid, {:update_tesla_state, tesla_state})
    end)

    {:noreply, %{state | tesla_state: tesla_state}}
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
