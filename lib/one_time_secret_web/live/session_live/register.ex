defmodule OneTimeSecretWeb.SessionLive.Register do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Organizations
  alias OneTimeSecret.Sessions
  alias OneTimeSecretWeb.Plugs.SessionAuth

  @impl true
  def mount(_params, _session, socket) do
    # Get client metadata during mount
    user_agent = get_connect_info(socket, :user_agent)
    peer_data = get_connect_info(socket, :peer_data)

    ip_address =
      case peer_data do
        %{address: address} -> ip_to_string(address)
        _ -> nil
      end

    form = to_form(%{"email" => "", "password" => ""})

    {:ok,
     socket
     |> assign(:page_title, "Sign Up")
     |> assign(:form, form)
     |> assign(:error, nil)
     |> assign(:registering, false)
     |> assign(:user_agent, user_agent)
     |> assign(:ip_address, ip_address)}
  end

  @impl true
  def handle_event("validate", %{"register" => register_params}, socket) do
    form = to_form(register_params)
    {:noreply, assign(socket, form: form, error: nil)}
  end

  @impl true
  def handle_event("submit", %{"register" => %{"email" => email, "password" => password}}, socket) do
    socket = assign(socket, registering: true)

    attrs = %{
      email: email,
      password: password
    }

    case Organizations.register_account_with_personal_org(attrs) do
      {:ok, result} ->
        # Account created with personal org - now create session
        session_attrs = %{
          ip_address: socket.assigns.ip_address,
          user_agent: socket.assigns.user_agent
        }

        case Sessions.create_session(result.account, session_attrs) do
          {:ok, session} ->
            {:noreply,
             socket
             |> put_flash(:info, "Welcome to OneTimeSecret, #{email}!")
             |> SessionAuth.put_session_cookie(session.id)
             |> push_navigate(to: ~p"/dashboard")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:registering, false)
             |> assign(:error, "Account created but failed to log you in. Please try logging in.")}
        end

      {:error, :account, changeset, _changes} ->
        # Extract first error message
        error_message =
          case changeset.errors do
            [{:email, {msg, _}} | _] -> "Email #{msg}"
            [{:password, {msg, _}} | _] -> "Password #{msg}"
            _ -> "Invalid registration information"
          end

        {:noreply,
         socket
         |> assign(:registering, false)
         |> assign(:error, error_message)}

      {:error, _step, _changeset, _changes} ->
        {:noreply,
         socket
         |> assign(:registering, false)
         |> assign(:error, "Registration failed. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-md">
        <div class="mb-8 text-center">
          <h1 class="text-4xl font-bold text-base-content mb-2">Sign Up</h1>
          <p class="text-base-content/70">
            Create your account to start sharing secrets securely
          </p>
        </div>

        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <.form for={@form} id="register-form" phx-change="validate" phx-submit="submit">
              <div class="space-y-4">
                <div>
                  <label for="register-email" class="block text-sm font-medium text-base-content mb-2">
                    Email
                  </label>
                  <input
                    type="email"
                    id="register-email"
                    name="register[email]"
                    value={@form.params["email"]}
                    class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
                    placeholder="[email protected]"
                    required
                    autofocus
                  />
                </div>

                <div>
                  <label
                    for="register-password"
                    class="block text-sm font-medium text-base-content mb-2"
                  >
                    Password
                  </label>
                  <input
                    type="password"
                    id="register-password"
                    name="register[password]"
                    value={@form.params["password"]}
                    class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
                    placeholder="At least 12 characters"
                    required
                  />
                  <p class="text-sm text-base-content/60 mt-1">
                    Password must be at least 12 characters long
                  </p>
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

                <button type="submit" class="btn btn-primary w-full" disabled={@registering}>
                  <%= if @registering do %>
                    <span class="loading loading-spinner"></span> Creating account...
                  <% else %>
                    Create Account
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>

        <div class="text-center mt-6">
          <p class="text-sm text-base-content/70">
            Already have an account? <a href="/login" class="link link-primary">Log in</a>
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
