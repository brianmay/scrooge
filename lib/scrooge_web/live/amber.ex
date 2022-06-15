defmodule ScroogeWeb.Live.Amber do
  @moduledoc "Get Amber information"
  use ScroogeWeb, :live_view
  alias Scrooge.Amber.Worker

  def mount(_params, _session, socket) do
    date = DateTime.utc_now() |> DateTime.shift_zone!(timezone()) |> DateTime.to_date()

    assigns = [
      active: "amber",
      date: Date.to_string(date),
      prices_error: nil,
      prices: nil,
      usage_error: nil,
      usage: nil,
      loading: false
    ]

    socket = assign(socket, assigns)

    if connected?(socket) do
      Worker.subscribe()
    end

    {:ok, socket}
  end

  def handle_event("search", %{"date" => params}, socket) do
    assigns = [
      prices_error: nil,
      prices: nil,
      usage_error: nil,
      usage: nil,
      date: params
    ]

    socket = assign(socket, assigns)

    socket =
      case {socket.assigns.loading, Date.from_iso8601(params)} do
        {true, _} ->
          nil

        {false, {:ok, date}} ->
          end_date = Date.add(date, 0)
          Supervisor.start_link([{Worker, {date, end_date}}], strategy: :one_for_one)
          assign(socket, :loading, true)

        {false, {:error, _error}} ->
          socket
          |> assign(:prices_error, "Got error parsing date")
          |> assign(:usage_error, "Got error parsing date")
          |> assign(:prices, nil)
          |> assign(:usage, nil)
      end

    {:noreply, socket}
  end

  def handle_info({:prices, prices}, socket) do
    socket =
      case prices do
        {:ok, prices} ->
          assign(socket, :prices, prices)

        {:error, error} ->
          assign(socket, :prices_error, error)
      end

    {:noreply, socket}
  end

  def handle_info({:usage, usage}, socket) do
    socket =
      case usage do
        {:ok, usage} ->
          assign(socket, :usage, usage)

        {:error, error} ->
          assign(socket, :usage_error, error)
      end

    {:noreply, socket}
  end

  def handle_info({:done}, socket) do
    socket = assign(socket, :loading, false)
    {:noreply, socket}
  end
end
