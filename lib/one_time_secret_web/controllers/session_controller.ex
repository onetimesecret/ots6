defmodule OneTimeSecretWeb.SessionController do
  use OneTimeSecretWeb, :controller

  alias OneTimeSecret.Sessions
  alias OneTimeSecretWeb.Plugs.SessionAuth

  @doc """
  Activates a session by setting the cookie and redirecting to dashboard.

  Called after successful login from the LiveView, which creates the session
  record and redirects here with the session ID in the query params.
  """
  def activate(conn, %{"id" => session_id}) do
    session = Sessions.get_session!(session_id)

    # Check if session is expired
    now = DateTime.utc_now()

    if DateTime.compare(session.expires_at, now) == :gt do
      # Session valid - set cookie and redirect
      conn
      |> SessionAuth.put_session_cookie(session_id)
      |> put_flash(:info, "Welcome back!")
      |> redirect(to: ~p"/dashboard")
    else
      # Session expired
      conn
      |> put_flash(:error, "Session expired. Please log in again.")
      |> redirect(to: ~p"/login")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Invalid session. Please log in again.")
      |> redirect(to: ~p"/login")
  end

  @doc """
  Logs out the current user by terminating the session.

  Removes the session record from the database and clears the cookie.
  """
  def delete(conn, _params) do
    session_id = get_session(conn, "_one_time_secret_session_id")

    if session_id do
      # Try to terminate the session (ignore errors if already gone)
      try do
        session = Sessions.get_session!(session_id)
        Sessions.terminate_session(session)
      rescue
        Ecto.NoResultsError -> :ok
      end
    end

    conn
    |> SessionAuth.clear_session_cookie()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end
end
