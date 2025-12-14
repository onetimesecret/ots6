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
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        # Validate session isn't expired
        case Sessions.validate_session(session) do
          {:ok, _session} ->
            conn
            |> SessionAuth.put_session_cookie(session_id)
            |> put_flash(:info, "Welcome back!")
            |> redirect(to: ~p"/dashboard")

          {:error, :expired} ->
            conn
            |> put_flash(:error, "Session expired. Please log in again.")
            |> redirect(to: ~p"/login")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid session. Please log in again.")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  Logs out the current user by terminating the session.

  Removes the session record from the database and clears the cookie.
  """
  def delete(conn, _params) do
    session_id = SessionAuth.session_cookie_key() |> then(&get_session(conn, &1))

    if session_id do
      # Try to terminate the session (ignore errors if already gone)
      case Sessions.get_session(session_id) do
        {:ok, session} -> Sessions.terminate_session(session)
        {:error, _} -> :ok
      end
    end

    conn
    |> SessionAuth.clear_session_cookie()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end
end
