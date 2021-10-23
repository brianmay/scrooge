defmodule ScroogeWeb.SessionController do
  use ScroogeWeb, :controller

  alias ScroogeWeb.Router.Helpers, as: Routes

  def oidc_login_url do
    OpenIDConnect.authorization_uri(:client)
  end

  def new(conn, _) do
    next = conn.query_params["next"]

    conn
    |> put_session(:next_url, next)
    |> redirect(external: oidc_login_url())
  end

  def logout(conn, _) do
    user = conn.assigns.user

    if Scrooge.User.user_signed_in?(user) do
      ScroogeWeb.Endpoint.broadcast("users_socket:#{user.sub}", "disconnect", %{})
    end

    conn
    |> clear_session()
    |> redirect(to: Routes.page_path(conn, :index))
  end

  def create(conn, params) do
    next =
      case get_session(conn, :next_url) do
        "" -> Routes.page_path(conn, :index)
        nil -> Routes.page_path(conn, :index)
        next -> next
      end

    conn = clear_session(conn)
    code = params["code"]

    with {:ok, tokens} <- OpenIDConnect.fetch_tokens(:client, %{code: code}),
         {:ok, claims} <- OpenIDConnect.verify(:client, tokens["id_token"]) do
      filtered_claims = Map.take(claims, ["name", "groups", "sub"])
      sub = claims["sub"]

      conn
      |> put_flash(:info, "Welcome back!")
      |> put_session(:live_socket_id, "users_socket:#{sub}")
      |> put_session(:claims, filtered_claims)
      |> redirect(to: next)
    else
      _ ->
        conn
        |> put_flash(:danger, "Invalid credentials")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end
end
