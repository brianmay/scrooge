defmodule ScroogeWeb.ViewHelpers do
  @moduledoc """
  Define helper functions for views
  """
  alias Phoenix.HTML.Link

  def valid(value), do: not is_nil(value)

  def timezone, do: Application.get_env(:scrooge, :timezone)

  def date_time_to_str(dt) do
    DateTime.to_iso8601(dt)
  end

  def parse_date_time(str) do
    {:ok, dt, _} = DateTime.from_iso8601(str)
    dt
  end

  def date_time_to_local(nil), do: nil

  def date_time_to_local(dt) do
    dt
    |> DateTime.shift_zone!(timezone())
    |> Timex.format!("%F %T", :strftime)
  end

  @spec door_state(boolean) :: String.t()
  def door_state(value) do
    case value do
      true -> "Opened"
      false -> "Closed"
    end
  end

  # defp div_rem(value, divider) do
  #   {div(value, divider), rem(value, divider)}
  # end

  # defp pad(number, digits) do
  #   number
  #   |> Integer.to_string()
  #   |> String.pad_leading(digits, "0")
  # end

  # defp format_distance(value) do
  #   value = round(value)
  #   {km, m} = div_rem(value, 1000)
  #   "#{km}.#{pad(m, 3)}km"
  # end

  def format_speed(nil), do: "nil"
  def format_speed(value), do: "#{round(value)}km/h"

  def location_link(latitude, longitude) do
    text = "#{latitude},#{longitude}"

    Link.link(text, to: "https://www.google.com/maps/search/#{latitude},#{longitude}")
  end

  def format_cents(cents) do
    trunc(Float.round(cents))
  end

  # defp format_cents_as_dollars(cents) do
  #   value = round(cents)
  #   {d, c} = div_rem(value, 100)
  #   "#{d}.#{pad(c, 2)}"
  # end

  def aemo_price_type("ACTUAL"), do: "A"
  def aemo_price_type("FORECAST"), do: "F"
end
