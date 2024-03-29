defmodule ScroogeWeb.InitAssigns do
  @moduledoc """
  Hook to intercept liveview mount requests
  """
  import Phoenix.LiveView

  alias ScroogeWeb.Router.Helpers, as: Routes

  def on_mount(:default, _params, session, socket) do
    user = session["claims"]

    if user == nil do
      socket = put_flash(socket, :danger, "Your session has expired.")
      socket = redirect(socket, to: Routes.page_path(socket, :index))
      {:halt, socket}
    else
      socket = assign(socket, :current_user, user)
      {:cont, socket}
    end
  end
end
