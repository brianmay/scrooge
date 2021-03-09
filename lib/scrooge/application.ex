defmodule Scrooge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def get_tortoise_client_id do
    {:ok, hostname} = :inet.gethostname()
    hostname = to_string(hostname)
    "scrooge-#{hostname}"
  end

  def start(_type, _args) do
    # List all child processes to be supervised

    mqtt_host = Application.get_env(:scrooge, :mqtt_host)
    mqtt_port = Application.get_env(:scrooge, :mqtt_port)
    ca_cert_file = Application.get_env(:scrooge, :ca_cert_file)
    user_name = Application.get_env(:scrooge, :mqtt_user_name)
    password = Application.get_env(:scrooge, :mqtt_password)

    children = [
      # Start the Ecto repository
      Scrooge.Repo,
      Scrooge.TeNerves,
      # Start the endpoint when the application starts
      ScroogeWeb.Endpoint,
      {Phoenix.PubSub, [name: Scrooge.PubSub, adapter: Phoenix.PubSub.PG2]},
      # Start Aemo process
      {Scrooge.Aemo, []},
      # Start MQTT processes
      {Scrooge.Tesla, []},
      {Tortoise.Connection,
       client_id: get_tortoise_client_id(),
       handler: {Scrooge.MqttHandler, []},
       user_name: user_name,
       password: password,
       server: {
         Tortoise.Transport.SSL,
         host: mqtt_host, port: mqtt_port, cacertfile: ca_cert_file
       },
       subscriptions: [
         {"teslamate/cars/1/#", 0}
       ]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Scrooge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ScroogeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
