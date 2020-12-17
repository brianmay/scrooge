defmodule Scrooge.TeNerves do
  @moduledoc "TeNerves database support"
  use Ecto.Repo,
    otp_app: :scrooge,
    adapter: Ecto.Adapters.Postgres
end
