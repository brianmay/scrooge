defmodule ScroogeWeb.LiveView do
  use ScroogeWeb, :view

  @timezone Application.get_env(:scrooge, :timezone)

  defp str_to_date_time(nil), do: nil

  defp str_to_date_time(str) do
    {:ok, dt, 0} = DateTime.from_iso8601(str)
    dt
  end

  defp date_time_to_str(dt) do
    DateTime.to_iso8601(dt)
  end

  defp date_time_to_local(nil), do: nil

  defp date_time_to_local(dt) do
    dt
    |> DateTime.shift_zone!(@timezone)
    |> Timex.format!("%F %T", :strftime)
  end

  defp door_state(value) do
    case value do
      0 -> "Closed"
      x -> "Open #{x}"
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

  defp format_time_minutes(nil), do: nil

  defp format_time_minutes(value) do
    {negative_sign, value} =
      if value < 0 do
        {"-", -value}
      else
        {"", value}
      end

    value = round(value)
    {hours, minutes} = div_rem(value, 60)
    "#{negative_sign}#{pad(hours, 2)}:#{pad(minutes, 2)}"
  end

  defp format_time_hours(nil), do: nil

  defp format_time_hours(value) do
    format_time_minutes(value * 60)
  end

  defp format_speed(nil), do: "nil"
  defp format_speed(value), do: "#{round(value)}km/h"

  defp location_link(latitude, longitude) do
    text = "#{latitude},#{longitude}"

    Phoenix.HTML.Link.link(text, to: "https://www.google.com/maps/search/#{latitude},#{longitude}")
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
