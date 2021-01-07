defmodule ScroogeWeb.LiveView do
  use ScroogeWeb, :view

  alias Phoenix.HTML.Link

  defp valid(value), do: not is_nil(value)

  defp timezone, do: Application.get_env(:scrooge, :timezone)

  defp date_time_to_str(dt) do
    DateTime.to_iso8601(dt)
  end

  defp date_time_to_local(nil), do: nil

  defp date_time_to_local(dt) do
    dt
    |> DateTime.shift_zone!(timezone())
    |> Timex.format!("%F %T", :strftime)
  end

  defp door_state(value) do
    case value do
      true -> "Opened"
      false -> "Closed"
    end
  end

  defp div_rem(value, divider) do
    {div(value, divider), rem(value, divider)}
  end

  defp pad(number, digits) do
    number
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp format_distance(value) do
    value = round(value)
    {km, m} = div_rem(value, 1000)
    "#{km}.#{pad(m, 3)}km"
  end

  @spec format_time_minutes(integer() | nil) :: String.t() | nil
  defp format_time_minutes(nil), do: nil

  defp format_time_minutes(value) do
    {negative_sign, signed_value} =
      if value < 0 do
        {"-", -value}
      else
        {"", value}
      end

    signed_value = round(signed_value)
    {hours, minutes} = div_rem(signed_value, 60)
    "#{negative_sign}#{pad(hours, 2)}:#{pad(minutes, 2)}"
  end

  @spec format_time_hours(integer() | nil) :: String.t() | nil
  defp format_time_hours(nil), do: nil

  defp format_time_hours(value) do
    format_time_minutes(value * 60)
  end

  defp format_speed(nil), do: "nil"
  defp format_speed(value), do: "#{round(value)}km/h"

  defp location_link(latitude, longitude) do
    text = "#{latitude},#{longitude}"

    Link.link(text, to: "https://www.google.com/maps/search/#{latitude},#{longitude}")
  end

  defp format_cents(cents) do
    trunc(Float.round(cents))
  end

  defp format_cents_as_dollars(cents) do
    value = round(cents)
    {d, c} = div_rem(value, 100)
    "#{d}.#{pad(c, 2)}"
  end

  defp aemo_price_type("ACTUAL"), do: "A"
  defp aemo_price_type("FORECAST"), do: "F"
end
