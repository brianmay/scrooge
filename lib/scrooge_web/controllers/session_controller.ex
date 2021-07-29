defmodule ScroogeWeb.SessionController do
  use ScroogeWeb, :controller

  alias Scrooge.{Accounts, Accounts.Guardian, Accounts.User}
  alias ScroogeWeb.Router.Helpers, as: Routes

  def new(conn, _) do
    changeset = Accounts.change_user(%User{})
    next = conn.query_params["next"]

    render(conn, "new.html",
      changeset: changeset,
      action: Routes.session_path(conn, :new, next: next),
      active: "login"
    )
  end

  def login(conn, %{"user" => %{"username" => username, "password" => password}}) do
    Accounts.authenticate_user(username, password)
    |> login_reply(conn)
  end

  def logout(conn, _) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      ScroogeWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
    end

    conn
    |> Guardian.Plug.sign_out()
    |> redirect(to: Routes.session_path(conn, :new))
  end

  defp login_reply({:ok, user}, conn) do
    next =
      case conn.query_params["next"] do
        "" -> Routes.page_path(conn, :index)
        nil -> Routes.page_path(conn, :index)
        next -> next
      end

    conn
    |> put_flash(:info, "Welcome back!")
    |> put_session(:live_socket_id, "users_socket:#{user.id}")
    |> Guardian.Plug.sign_in(user)
    |> redirect(to: next)
  end

  defp login_reply({:error, _reason}, conn) do
    conn
    |> put_flash(:danger, "Invalid credentials")
    |> new(%{})
  end
end
