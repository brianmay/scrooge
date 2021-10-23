defmodule ScroogeWeb.Plug.Auth do
  @moduledoc "OIDC authentication pipeline"
  import Plug.Conn
  use ScroogeWeb, :controller

  def init(_params) do
  end

  def call(conn, _params) do
    claims = get_session(conn, :claims)
    user = Scrooge.User.claims_to_user(claims)
    assign(conn, :user, user)
  end
end
