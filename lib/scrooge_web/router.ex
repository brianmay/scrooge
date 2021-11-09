defmodule ScroogeWeb.Router do
  use ScroogeWeb, :router

  use Plugoid.RedirectURI,
    token_callback: &ScroogeWeb.TokenCallback.callback/5

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ScroogeWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  defmodule PlugoidConfig do
    def common do
      config = Application.get_env(:scrooge, :oidc)

      [
        issuer: config.discovery_document_uri,
        client_id: config.client_id,
        scope: String.split(config.scope, " "),
        client_config: ScroogeWeb.ClientCallback
      ]
    end
  end

  pipeline :auth do
    plug Replug,
      plug: {Plugoid, on_unauthenticated: :pass},
      opts: {PlugoidConfig, :common}
  end

  pipeline :ensure_auth do
    plug Replug,
      plug: {Plugoid, on_unauthenticated: :auth},
      opts: {PlugoidConfig, :common}
  end

  pipeline :ensure_admin do
    plug ScroogeWeb.Plug.CheckAdmin
  end

  live_session :default, on_mount: ScroogeWeb.InitAssigns do
    scope "/", ScroogeWeb do
      pipe_through [:browser, :auth]

      get "/", PageController, :index
      post "/logout", PageController, :logout
    end

    scope "/", ScroogeWeb do
      pipe_through [:browser, :auth, :ensure_auth]
      get "/login", PageController, :login
      live "/aemo", Live.Aemo, :index
      live "/tesla", Live.Tesla, :index
    end
  end

  scope "/", ScroogeWeb do
    pipe_through [:browser, :auth, :ensure_admin]
    live_dashboard "/dashboard", metrics: ScroogeWeb.Telemetry
  end
end
