defmodule OneTimeSecretWeb.SessionLive.New do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Accounts
  alias OneTimeSecret.Sessions
  alias OneTimeSecretWeb.Plugs.SessionAuth

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => "", "password" => ""})

    {:ok,
     socket
     |> assign(:page_title, "Log In")
     |> assign(:form, form)
     |> assign(:error, nil)
     |> assign(:authenticating, false)}
  end

  @impl true
  def handle_event("validate", %{"login" => login_params}, socket) do
    form = to_form(login_params)
    {:noreply, assign(socket, form: form, error: nil)}
  end

  @impl true
  def handle_event("submit", %{"login" => %{"email" => email, "password" => password}}, socket) do
    socket = assign(socket, authenticating: true)

    case Accounts.authenticate_account(email, password) do
      {:ok, account} ->
        # Get client metadata for session
        user_agent = get_connect_info(socket, :user_agent)
        peer_data = get_connect_info(socket, :peer_data)

        ip_address =
          case peer_data do
            %{address: address} -> ip_to_string(address)
            _ -> nil
          end

        session_attrs = %{
          ip_address: ip_address,
          user_agent: user_agent
        }

        case Sessions.create_session(account, session_attrs) do
          {:ok, session} ->
            {:noreply,
             socket
             |> put_flash(:info, "Welcome back, #{account.email}!")
             |> SessionAuth.put_session_cookie(session.id)
             |> push_navigate(to: ~p"/dashboard")}

          {:error, :no_organizations} ->
            {:noreply,
             socket
             |> assign(:authenticating, false)
             |> assign(
               :error,
               "Your account has no organizations. Please contact support."
             )}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:authenticating, false)
             |> assign(:error, "Failed to create session. Please try again.")}
        end

      {:error, :invalid_credentials} ->
        {:noreply,
         socket
         |> assign(:authenticating, false)
         |> assign(:error, "Invalid email or password")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-md">
        <div class="mb-8 text-center">
          <h1 class="text-4xl font-bold text-base-content mb-2">Log In</h1>
          <p class="text-base-content/70">
            Sign in to access your workspace
          </p>
        </div>

        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <.form for={@form} id="login-form" phx-change="validate" phx-submit="submit">
              <div class="space-y-4">
                <div>
                  <label for="login-email" class="block text-sm font-medium text-base-content mb-2">
                    Email
                  </label>
                  <input
                    type="email"
                    id="login-email"
                    name="login[email]"
                    value={@form.params["email"]}
                    class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
                    placeholder="[email protected]"
                    required
                    autofocus
                  />
                </div>

                <div>
                  <label for="login-password" class="block text-sm font-medium text-base-content mb-2">
                    Password
                  </label>
                  <input
                    type="password"
                    id="login-password"
                    name="login[password]"
                    value={@form.params["password"]}
                    class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
                    placeholder="Enter your password"
                    required
                  />
                </div>

                <%= if @error do %>
                  <div class="alert alert-error">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="stroke-current shrink-0 h-6 w-6"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    <span>{@error}</span>
                  </div>
                <% end %>

                <button type="submit" class="btn btn-primary w-full" disabled={@authenticating}>
                  <%= if @authenticating do %>
                    <span class="loading loading-spinner"></span> Signing in...
                  <% else %>
                    Sign In
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>

        <div class="text-center mt-6">
          <p class="text-sm text-base-content/70">
            Don't have an account? <a href="/register" class="link link-primary">Sign up</a>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Private Helpers

  defp ip_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp ip_to_string({a, b, c, d, e, f, g, h}),
    do: "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"

  defp ip_to_string(_), do: nil
end
