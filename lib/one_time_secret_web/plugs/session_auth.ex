defmodule OneTimeSecretWeb.Plugs.SessionAuth do
  @moduledoc """
  Plug for session-based authentication.

  Provides two plugs:
  - `fetch_current_session/2` - Reads session cookie, validates, populates assigns
  - `require_authenticated/2` - Redirects to login if no valid session

  ## Usage

  In your router:

      pipeline :authenticated do
        plug :fetch_current_session
        plug :require_authenticated
      end

      scope "/", MyAppWeb do
        pipe_through [:browser, :authenticated]
        live "/dashboard", DashboardLive
      end

  """

  import Plug.Conn
  import Phoenix.Controller

  alias OneTimeSecret.Sessions

  @doc """
  Fetches the current session from cookie and validates it.

  If valid, populates:
  - `conn.assigns.current_session`
  - `conn.assigns.current_account`
  - `conn.assigns.current_organization`

  If invalid or missing, sets all to `nil`.

  Always allows request to proceed (doesn't halt).
  """
  def fetch_current_session(conn, _opts) do
    session_id = get_session(conn, Sessions.session_cookie_key())

    case validate_and_fetch_session(session_id) do
      {:ok, session} ->
        conn
        |> assign(:current_session, session)
        |> assign(:current_account, session.account)
        |> assign(:current_organization, session.active_organization)

      {:error, _reason} ->
        conn
        |> assign(:current_session, nil)
        |> assign(:current_account, nil)
        |> assign(:current_organization, nil)
    end
  end

  @doc """
  Requires a valid authenticated session.

  If no valid session, redirects to login page and halts the pipeline.

  Must be used after `fetch_current_session/2`.
  """
  def require_authenticated(conn, _opts) do
    if conn.assigns[:current_account] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Stores a session ID in the connection's session cookie.

  ## Examples

      iex> put_session_cookie(conn, session.id)
      %Plug.Conn{}

  """
  def put_session_cookie(conn, session_id) when is_binary(session_id) do
    put_session(conn, Sessions.session_cookie_key(), session_id)
  end

  @doc """
  Clears the session cookie.

  ## Examples

      iex> clear_session_cookie(conn)
      %Plug.Conn{}

  """
  def clear_session_cookie(conn) do
    delete_session(conn, Sessions.session_cookie_key())
  end

  # Private Helpers

  defp validate_and_fetch_session(nil), do: {:error, :no_session_cookie}

  defp validate_and_fetch_session(session_id) when is_binary(session_id) do
    Sessions.validate_session(session_id)
  end
end
