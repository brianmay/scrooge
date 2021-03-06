import Config

port = String.to_integer(System.get_env("PORT") || "4000")

config :scrooge,
  mqtt_host: System.get_env("MQTT_HOST"),
  mqtt_port: String.to_integer(System.get_env("MQTT_PORT") || "8883"),
  ca_cert_file: System.get_env("MQTT_CA_CERT_FILE"),
  mqtt_user_name: System.get_env("MQTT_USER_NAME"),
  mqtt_password: System.get_env("MQTT_PASSWORD"),
  robotica: System.get_env("ROBOTICA") != nil

config :scrooge, Scrooge.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :scrooge, Scrooge.Accounts.Guardian,
  issuer: "scrooge",
  secret_key: System.get_env("GUARDIAN_SECRET")

config :scrooge, ScroogeWeb.Endpoint,
  http: [:inet6, port: port],
  url: [host: System.get_env("HTTP_HOST") || System.get_env("HOST"), port: port],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  live_view: [
    signing_salt: System.get_env("SIGNING_SALT")
  ]

config :libcluster,
  topologies: [
    k8s: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "scrooge",
        kubernetes_selector: System.get_env("KUBERNETES_SELECTOR"),
        kubernetes_namespace: System.get_env("NAMESPACE"),
        polling_interval: 10_000
      ]
    ]
  ]
