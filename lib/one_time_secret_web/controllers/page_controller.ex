defmodule OneTimeSecretWeb.PageController do
  use OneTimeSecretWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
