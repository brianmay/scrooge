defmodule ScroogeWeb.Router do
  use ScroogeWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ScroogeWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug ScroogeWeb.Plug.Auth
  end

  # We use ensure_auth to fail if there is no one logged in
  pipeline :ensure_auth do
    plug Guardian.Plug.EnsureAuthenticated
  end

  pipeline :ensure_admin do
    plug Guardian.Plug.EnsureAuthenticated
    plug ScroogeWeb.Plug.CheckAdmin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ScroogeWeb do
    pipe_through [:browser, :auth]

    get "/", PageController, :index
    get "/login", SessionController, :new
    post "/login", SessionController, :login
    post "/logout", SessionController, :logout
    get("/callback", SessionController, :create)
  end

  scope "/", ScroogeWeb do
    pipe_through [:browser, :auth, :ensure_auth]
    live "/aemo", Live.Aemo, :index
    live "/tesla", Live.Tesla, :index
  end

  scope "/", ScroogeWeb do
    pipe_through [:browser, :auth, :ensure_admin]

    resources "/users", UserController
    get "/users/:id/password", UserController, :password_edit
    put "/users/:id/password", UserController, :password_update
    live_dashboard "/dashboard", metrics: ScroogeWeb.Telemetry
  end

  # Other scopes may use custom stacks.
  # scope "/api", ScroogeWeb do
  #   pipe_through :api
  # end
end
