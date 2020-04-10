import Config

port = String.to_integer(System.get_env("PORT") || "4000")

config :scrooge, Scrooge.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :scrooge, ScroogeWeb.Endpoint,
  http: [:inet6, port: port],
  url: [host: System.get_env("HOST"), port: port],
  secret_key_base: System.get_env("SECRET_KEY_BASE")
