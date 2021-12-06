defmodule Scrooge.MqttMultiplexer do
  @moduledoc """
  Implement per process MQTT subscriptions
  """
  use GenServer
  require Logger

  defmodule State do
    @moduledoc """
    Define current state of Subscriptions.
    """
    @type t :: %__MODULE__{
            subscriptions: %{list(String.t()) => list({String.t(), pid, :json | :raw})},
            last_message: %{list(String.t()) => any()},
            monitor: %{required(pid) => reference()}
          }
    defstruct subscriptions: %{}, last_message: %{}, monitor: %{}
  end

  ## Client API

  @spec start_link(opts :: list) :: {:ok, pid} | {:error, String.t()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])
  end

  @spec subscribe(
          topic :: list(String.t()),
          label :: atom(),
          pid :: pid,
          format :: :json | :raw,
          resend :: :resend | :no_resend
        ) :: :ok
  def subscribe(topic, label, pid, format, resend) do
    GenServer.cast(__MODULE__, {:subscribe, topic, label, pid, format, resend})
  end

  @spec unsubscribe_all(pid :: pid) :: :ok
  def unsubscribe_all(pid) do
    GenServer.cast(__MODULE__, {:unsubscribe_all, pid})
    :ok
  end

  @spec message(topic :: String.t(), message :: String.t()) :: :ok
  def message(topic, message) do
    GenServer.cast(__MODULE__, {:message, topic, message})
  end

  ## private

  @spec get_message_format(String.t(), :json | :raw) :: {:ok, any()} | {:error, String.t()}
  def get_message_format(message, :json) do
    case Jason.decode(message) do
      {:ok, message} -> {:ok, message}
      {:error, error} -> {:error, "Error #{inspect(error)}"}
    end
  end

  def get_message_format(message, :raw), do: {:ok, message}

  ## Server Callbacks

  def init(:ok) do
    {:ok, %State{}}
  end

  def retry(_func, 0), do: :error

  def retry(func, tries) do
    Logger.info("Trying")

    case func.() do
      :ok ->
        Logger.info("got OK")
        :ok

      {:error, :timeout} ->
        Logger.info("got timeout")
        retry(func, tries - 1)
    end
  end

  @spec send_to_client(topic :: list(String.t()), any(), pid, atom(), String.t()) :: :ok
  defp send_to_client(topic, label, pid, format, raw_message) do
    case get_message_format(raw_message, format) do
      {:ok, message} ->
        Logger.debug(
          "Dispatching #{inspect(topic)} #{inspect(raw_message)} #{inspect(format)} #{inspect(message)}."
        )

        :ok = GenServer.cast(pid, {:mqtt, topic, label, message})

      {:error, message} ->
        Logger.error("Cannot decode #{inspect(message)} using #{inspect(format)}.")
    end
  end

  @spec handle_add(
          state :: State.t(),
          topic :: String.t(),
          label :: any(),
          pid :: pid,
          format :: :json | :raw,
          resend :: :resend | :no_resend
        ) ::
          State.t()
  defp handle_add(state, topic, label, pid, format, resend) do
    topic_str = Enum.join(topic, "/")

    state =
      if Map.has_key?(state.monitor, pid) do
        state
      else
        ref = Process.monitor(pid)
        monitor = Map.put(state.monitor, pid, ref)
        %State{state | monitor: monitor}
      end

    pids =
      case Map.get(state.subscriptions, topic, nil) do
        nil ->
          subscription = {topic_str, qos: 0, nl: true}
          client_name = Scrooge.Mqtt

          # Logger.info("- Unsubscribing to #{topic} pid #{inspect(pid)}.")
          # MqttPotion.unsubscribe(client_name, topic)
          Logger.info("- Subscribing to #{topic_str} pid #{inspect(pid)}.")
          MqttPotion.subscribe(client_name, subscription)

          Logger.debug("Adding pid #{inspect(pid)} to new subscription #{topic_str}.")
          [{label, pid, format}]

        pids ->
          Logger.debug("Adding pid #{inspect(pid)} to old subscription #{topic_str}.")
          [{label, pid, format} | pids]
      end

    subscriptions = Map.put(state.subscriptions, topic, pids)

    # resend last message to new client
    if resend == :resend do
      get_last_messages(state, topic)
      |> Enum.each(fn {last_topic, last_message} ->
        Logger.info("Resending last message to #{inspect(pid)} from subscription #{topic_str}.")
        :ok = send_to_client(last_topic, label, pid, format, last_message)
      end)
    end

    %State{state | subscriptions: subscriptions}
  end

  def handle_cast({:subscribe, topic, label, pid, format, resend}, state) do
    new_state = handle_add(state, topic, label, pid, format, resend)
    {:noreply, new_state}
  end

  def handle_cast({:unsubscribe_all, pid}, state) do
    new_state = handle_unsubscribe_all(pid, state)
    {:noreply, new_state}
  end

  def handle_cast({:message, topic_str, message}, state) do
    topic = String.split(topic_str, "/")
    Logger.info("Got message #{topic_str} #{inspect(message)}.")

    last_message = Map.put(state.last_message, topic, message)
    state = %State{state | last_message: last_message}

    get_subscriptions(state, topic)
    |> Enum.each(fn {label, pid, format} ->
      :ok = send_to_client(topic, label, pid, format, message)
    end)

    {:noreply, state}
  end

  defp get_last_messages(state, abbrev_topic) do
    Enum.filter(state.last_message, fn {full_topic, _} ->
      compare_topics(abbrev_topic, full_topic)
    end)
  end

  defp get_subscriptions(state, full_topic) do
    Enum.filter(state.subscriptions, fn {abbrev_topic, _} ->
      compare_topics(abbrev_topic, full_topic)
    end)
    |> Enum.map(fn {_, subscription} -> subscription end)
    |> List.flatten()
  end

  defp compare_topics([], []), do: true
  defp compare_topics(["#"], _), do: true

  defp compare_topics(["+" | abbrev_topic], [_ | full_topic]),
    do: compare_topics(abbrev_topic, full_topic)

  defp compare_topics([head | abbrev_topic], [head | full_topic]),
    do: compare_topics(abbrev_topic, full_topic)

  defp compare_topics(_, _), do: false

  @spec keyword_list_to_map(values :: list) :: map
  defp keyword_list_to_map(values) do
    for {key, val} <- values, into: %{}, do: {key, val}
  end

  @spec delete_pid_from_list(list, pid) :: list
  defp delete_pid_from_list(list, pid) do
    Enum.reject(list, fn {_, list_pid, _} -> list_pid == pid end)
  end

  def handle_info({{Tortoise, _}, _, _}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Logger.debug("Process #{inspect(pid)} #{inspect(ref)} died reason #{inspect(reason)}.")
    new_state = handle_unsubscribe_all(pid, state)
    {:noreply, new_state}
  end

  defp handle_unsubscribe_all(pid, state) do
    Logger.info("Removing pid #{inspect(pid)} from all subscriptions.")
    monitor = Map.delete(state.monitor, pid)

    new_subscriptions =
      state.subscriptions
      |> Enum.map(fn {topic, l} -> {topic, delete_pid_from_list(l, pid)} end)
      |> keyword_list_to_map()

    Enum.each(new_subscriptions, fn
      {topic, []} ->
        client_name = PenguinNodes.Mqtt
        topic_str = Enum.join(topic, "/")
        Logger.info("+ Unsubscribing from #{topic_str}.")
        MqttPotion.unsubscribe(client_name, topic)

      {_, _} ->
        nil
    end)

    new_subscriptions =
      new_subscriptions
      |> Enum.reject(fn
        {_, []} -> true
        {_, _} -> false
      end)
      |> keyword_list_to_map()

    %State{state | subscriptions: new_subscriptions, monitor: monitor}
  end
end
