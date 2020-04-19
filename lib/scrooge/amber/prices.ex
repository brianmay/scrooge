defmodule Scrooge.Amber.Prices do
  @moduledoc false

  def get_network_tarif(_, l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # "Schedule of Tariffs"
    {peak, shoulder, off_peak} =
      cond do
        Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> {14.8340, 11.5662, 4.3576}
        Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> {13.9065, 10.7419, 3.9028}
        Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> {13.1880, 10.1890, 3.0724}
      end

    day_of_week = Date.day_of_week(l_dt)

    case {day_of_week, l_dt.hour} do
      {dow, hour} when dow in 1..5 and hour in 15..20 ->
        peak

      {_, hour} when hour in 7..21 ->
        shoulder

      {_, _} ->
        off_peak
    end
  end

  def get_distribution_loss_factors(l_dt) do
    # https://aemo.com.au/energy-systems/electricity/national-electricity-market-nem/market-operations/loss-factors-and-regional-boundaries
    # "Distribution Loss Factors for the 2020-21 Financial Year"
    cond do
      Date.compare(l_dt, ~D[2020-07-01]) in [:eq, :gt] -> 1.0602
      Date.compare(l_dt, ~D[2019-07-01]) in [:eq, :gt] -> 1.0583
      Date.compare(l_dt, ~D[2018-07-01]) in [:eq, :gt] -> 1.0597
    end
  end

  def get_green_tarif(_l_dt) do
    # FIXME: Need to check source
    1.9
  end

  def get_market_environment_tarif(_l_dt) do
    # FIXME: Need to check source
    2.06846258860692
  end

  def get_distribution_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    " Schedule of Tariffs"

    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 118.00 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 115.00 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 109.00 * 100
    end
  end

  def get_meter_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # "Schedule of Prescribed Metering"
    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 51.40 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 57.80 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 60.80 * 100
    end
  end
end
