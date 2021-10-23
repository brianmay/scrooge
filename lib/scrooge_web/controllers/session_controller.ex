defmodule ScroogeWeb.SessionController do
  use ScroogeWeb, :controller

  alias Scrooge.{Accounts, Accounts.Guardian, Accounts.User}
  alias ScroogeWeb.Router.Helpers, as: Routes

  def use_oidc_login do
    !!Application.get_env(:scrooge, :openid_connect_providers)
  end

  def oidc_login_url do
    OpenIDConnect.authorization_uri(:client)
  end

  def new(conn, _) do
    next = conn.query_params["next"]

    if use_oidc_login() do
      conn
      |> put_session(:next_url, next)
      |> redirect(external: oidc_login_url())
    else
      changeset = Accounts.change_user(%User{})

      render(conn, "new.html",
        changeset: changeset,
        action: Routes.session_path(conn, :new, next: next),
        active: "login"
      )
    end
  end

  def login(conn, %{"user" => %{"username" => username, "password" => password}}) do
    next =
      case conn.query_params["next"] do
        "" -> Routes.page_path(conn, :index)
        nil -> Routes.page_path(conn, :index)
        next -> next
      end

    Accounts.authenticate_user(username, password)
    |> login_reply(conn, next)
  end

  def logout(conn, _) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      ScroogeWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
    end

    conn
    |> Guardian.Plug.sign_out()
    |> redirect(to: Routes.page_path(conn, :index))
  end

  defp login_reply({:ok, user}, conn, next) do
    conn
    |> put_flash(:info, "Welcome back!")
    |> put_session(:live_socket_id, "users_socket:#{user.id}")
    |> Guardian.Plug.sign_in(user)
    |> redirect(to: next)
  end

  defp login_reply({:error, _reason}, conn, _next) do
    conn
    |> put_flash(:danger, "Invalid credentials")
    |> new(%{})
  end

  def create(conn, params) do
    next =
      case get_session(conn, :next_url) do
        "" -> Routes.page_path(conn, :index)
        nil -> Routes.page_path(conn, :index)
        next -> next
      end

    conn = delete_session(conn, :next_url)

    with {:ok, tokens} <- OpenIDConnect.fetch_tokens(:client, %{code: params["code"]}),
         {:ok, claims} <- OpenIDConnect.verify(:client, tokens["id_token"]) do
      IO.puts(inspect(claims))

      Accounts.authenticate_user(claims["name"])
      |> login_reply(conn, next)
    else
      _ ->
        conn
        |> put_flash(:danger, "Invalid credentials")
        |> new(%{})
    end
  end
end
