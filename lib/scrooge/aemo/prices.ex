defmodule Scrooge.Aemo.Prices do
  @moduledoc false

  def carbon_neutral_offset(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 0.1100
    end
  end

  def environmental_certificate_cost(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 1.8425
    end
  end

  def market_charges(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 0.0715
    end
  end

  def network_tarif(_, l_dt) do
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

  def price_protection_hedging(_l_dt) do
    0.5500
  end

  def loss_factor(l_dt) do
    # https://aemo.com.au/energy-systems/electricity/national-electricity-market-nem/market-operations/loss-factors-and-regional-boundaries
    # "Distribution Loss Factors for the 2020-21 Financial Year"
    cond do
      Date.compare(l_dt, ~D[2020-07-01]) in [:eq, :gt] -> 1.0602
      Date.compare(l_dt, ~D[2019-07-01]) in [:eq, :gt] -> 1.0583
      Date.compare(l_dt, ~D[2018-07-01]) in [:eq, :gt] -> 1.0597
    end
  end

  def aemo_annual(_l_dt) do
    120
  end

  def distribution_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # " Schedule of Tariffs"

    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 118.00 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 115.00 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 109.00 * 100
    end
  end

  def meter_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # "Schedule of Prescribed Metering"
    cond do
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 51.40 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 57.80 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 60.80 * 100
    end
  end
end
