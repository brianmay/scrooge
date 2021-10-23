defmodule ScroogeWeb.Plug.EnsureAuth do
  @moduledoc "OIDC authentication pipeline"
  import Plug.Conn
  use ScroogeWeb, :controller

  def init(_params) do
  end

  def call(%Plug.Conn{} = conn, _params) do
    user = conn.assigns.user

    if Scrooge.User.user_is_admin?(user) do
      conn
    else
      conn
      |> put_flash(:danger, "You must be logged in to access this.")
      |> redirect(to: Routes.page_path(conn, :index))
      |> halt()
    end
  end
end
