defmodule ScroogeWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.LiveView

  alias ScroogeWeb.Router.Helpers, as: Routes

  def assign_defaults(socket, session) do
    claims = session["claims"]
    user = Scrooge.User.claims_to_user(claims)

    if Scrooge.User.user_signed_in?(user) do
      socket
    else
      redirect(socket, to: Routes.session_path(socket, :new))
    end
  end
end
