defmodule Scrooge.Aemo.Rates do
  @moduledoc false
  # All prices here exclude GST

  @type price :: float()
  @type t :: %__MODULE__{
          carbon_neutral_offset: price(),
          environmental_certificate_cost: price(),
          market_charges: price(),
          network_tarif: price(),
          amber_annual: price(),
          amber_price_protection_hedging: price(),
          loss_factor: float(),
          aemo_annual: price(),
          distribution_annual_charges: price(),
          meter_annual_charges: price()
        }
  @enforce_keys [
    :carbon_neutral_offset,
    :environmental_certificate_cost,
    :market_charges,
    :network_tarif,
    :amber_annual,
    :amber_price_protection_hedging,
    :loss_factor,
    :aemo_annual,
    :distribution_annual_charges,
    :meter_annual_charges
  ]
  defstruct [
    :carbon_neutral_offset,
    :environmental_certificate_cost,
    :market_charges,
    :network_tarif,
    :amber_annual,
    :amber_price_protection_hedging,
    :loss_factor,
    :aemo_annual,
    :distribution_annual_charges,
    :meter_annual_charges
  ]

  def get_rates("3787", local_datetime) do
    %__MODULE__{
      carbon_neutral_offset: carbon_neutral_offset(local_datetime),
      environmental_certificate_cost: environmental_certificate_cost(local_datetime),
      market_charges: market_charges(local_datetime),
      network_tarif: network_tarif(local_datetime),
      amber_annual: amber_annual(local_datetime),
      amber_price_protection_hedging: amber_price_protection_hedging(local_datetime),
      loss_factor: loss_factor(local_datetime),
      aemo_annual: aemo_annual(local_datetime),
      distribution_annual_charges: distribution_annual_charges(local_datetime),
      meter_annual_charges: meter_annual_charges(local_datetime)
    }
  end

  defp carbon_neutral_offset(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 0.1000
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 0.1000
    end
  end

  defp environmental_certificate_cost(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 2.3810
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 1.6130
    end
  end

  defp market_charges(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 0.2260
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 15.836
    end
  end

  defp network_tarifs(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # "Schedule of Tariffs"
    {_peak, _shoulder, _off_peak} =
      cond do
        Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> {13.9316, 10.9293, 4.1243}
        Date.compare(l_dt, ~D[2021-02-01]) in [:eq, :gt] -> {14.8340, 11.5662, 4.3576}
        Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> {0.0000, 11.5662, 4.3576}
        Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> {0.0000, 10.7419, 3.9028}
        Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> {0.0000, 10.1890, 3.0724}
      end
  end

  defp network_tarif(l_dt) do
    {peak, shoulder, off_peak} = network_tarifs(l_dt)

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

  defp amber_annual(_l_dt) do
    109.08
  end

  defp amber_price_protection_hedging(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 0.7000
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 0.5000
    end
  end

  defp loss_factor(l_dt) do
    # https://aemo.com.au/energy-systems/electricity/national-electricity-market-nem/market-operations/loss-factors-and-regional-boundaries
    # "Distribution Loss Factors for the 2020-21 Financial Year"
    cond do
      Date.compare(l_dt, ~D[2021-07-01]) in [:eq, :gt] -> 1.0570
      Date.compare(l_dt, ~D[2020-07-01]) in [:eq, :gt] -> 1.0602
      Date.compare(l_dt, ~D[2019-07-01]) in [:eq, :gt] -> 1.0583
      Date.compare(l_dt, ~D[2018-07-01]) in [:eq, :gt] -> 1.0597
    end
  end

  defp aemo_annual(l_dt) do
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 106
      Date.compare(l_dt, ~D[2020-01-01]) in [:eq, :gt] -> 118
    end
  end

  defp distribution_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # " Schedule of Tariffs"

    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 106.00 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 115.00 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 109.00 * 100
    end
  end

  defp meter_annual_charges(l_dt) do
    # https://www.ausnetservices.com.au/Misc-Pages/Links/About-Us/Charges-and-revenues/Network-tariffs
    # "Schedule of Prescribed Metering"
    cond do
      Date.compare(l_dt, ~D[2021-03-01]) in [:eq, :gt] -> 71.38 * 100
      Date.compare(l_dt, ~D[2019-01-01]) in [:eq, :gt] -> 57.80 * 100
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 60.80 * 100
    end
  end
end
