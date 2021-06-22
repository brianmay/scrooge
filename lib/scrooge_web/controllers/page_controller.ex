defmodule ScroogeWeb.PageController do
  use ScroogeWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html", active: "index")
  end

  def tesla(conn, _params) do
    render(conn, "tesla.html", active: "tesla")
  end

  def aemo(conn, _params) do
    render(conn, "aemo.html", active: "aemo")
  end
end
