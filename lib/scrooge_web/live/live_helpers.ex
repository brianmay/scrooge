defmodule ScroogeWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.LiveView

  alias ScroogeWeb.Router.Helpers, as: Routes

  def assign_defaults(socket, session) do
    user =
      case Scrooge.Auth.load_user(session) do
        {:ok, user} -> user
        {:error, _} -> nil
        :not_logged_in -> nil
      end

    if user do
      socket
    else
      redirect(socket, to: Routes.session_path(socket, :new))
    end
  end
end
