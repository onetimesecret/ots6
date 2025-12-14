defmodule OneTimeSecretWeb.SessionLive.New do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Accounts
  alias OneTimeSecret.Sessions

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => "", "password" => ""})

    {:ok,
     socket
     |> assign(:page_title, "Log In")
     |> assign(:form, form)
     |> assign(:error, nil)
     |> assign(:logging_in, false)}
  end

  @impl true
  def handle_event("validate", %{"login" => login_params}, socket) do
    form = to_form(login_params)
    {:noreply, assign(socket, form: form, error: nil)}
  end

  @impl true
  def handle_event("submit", %{"login" => %{"email" => email, "password" => password}}, socket) do
    socket = assign(socket, logging_in: true)

    case Accounts.authenticate_account(email, password) do
      {:ok, account} ->
        case Sessions.create_session(account) do
          {:ok, session} ->
            # Redirect to controller that sets cookie and redirects to dashboard
            {:noreply, push_navigate(socket, to: ~p"/session/activate?id=#{session.id}")}

          {:error, :no_organizations} ->
            {:noreply,
             socket
             |> assign(:logging_in, false)
             |> assign(:error, "Your account has no organizations. Please contact support.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:logging_in, false)
             |> assign(:error, "Failed to create session. Please try again.")}
        end

      {:error, :invalid_credentials} ->
        {:noreply,
         socket
         |> assign(:logging_in, false)
         |> assign(:error, "Invalid email or password")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-md">
        <div class="mb-8 text-center">
          <h1 class="text-4xl font-bold text-base-content mb-2">Welcome Back</h1>
          <p class="text-base-content/70">
            Log in to access your secure workspace
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

                <button type="submit" class="btn btn-primary w-full" disabled={@logging_in}>
                  <%= if @logging_in do %>
                    <span class="loading loading-spinner"></span> Logging in...
                  <% else %>
                    Log In
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
end
