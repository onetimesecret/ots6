defmodule OneTimeSecretWeb.Live.Hooks.RequireAuthenticated do
  @moduledoc """
  LiveView on_mount hook that requires an authenticated session.

  LiveViews don't inherit conn.assigns, so this hook reads the session
  from the database and assigns current_account and current_organization
  to the socket.

  ## Usage

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view

        on_mount OneTimeSecretWeb.Live.Hooks.RequireAuthenticated

        # ...
      end
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias OneTimeSecret.Sessions

  def on_mount(:default, _params, session, socket) do
    session_id = session[Sessions.session_cookie_key()]

    case session_id && Sessions.validate_session(session_id) do
      {:ok, db_session} ->
        {:cont,
         assign(socket,
           current_account: db_session.account,
           current_organization: db_session.active_organization
         )}

      {:error, _reason} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end
end
