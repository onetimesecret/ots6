defmodule OneTimeSecretWeb.SessionController do
  use OneTimeSecretWeb, :controller

  alias OneTimeSecret.Sessions
  alias OneTimeSecretWeb.Plugs.SessionAuth

  @doc """
  Terminates the current session and redirects to home page.

  Deletes the session from the database and clears the session cookie.
  """
  def delete(conn, _params) do
    session_id = get_session(conn, Sessions.session_cookie_key())

    # Terminate session in database if it exists
    if session_id do
      Sessions.terminate_session(session_id)
    end

    conn
    |> SessionAuth.clear_session_cookie()
    |> put_flash(:info, "You have been logged out")
    |> redirect(to: ~p"/")
  end
end
