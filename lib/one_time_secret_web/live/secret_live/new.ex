defmodule OneTimeSecretWeb.SecretLive.New do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Secrets

  @ttl_options [
    {"5 minutes", 300},
    {"30 minutes", 1800},
    {"1 hour", 3600},
    {"4 hours", 14400},
    {"12 hours", 43200},
    {"1 day", 86400},
    {"7 days", 604_800}
  ]

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(%{
        "value" => "",
        "ttl_seconds" => "3600",
        "passphrase" => ""
      })

    {:ok,
     socket
     |> assign(:page_title, "Share a Secret")
     |> assign(:form, form)
     |> assign(:ttl_options, @ttl_options)
     |> assign(:creating, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("validate", %{"secret" => secret_params}, socket) do
    form = to_form(secret_params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("create", %{"secret" => secret_params}, socket) do
    %{"value" => value, "ttl_seconds" => ttl_str, "passphrase" => passphrase} = secret_params

    with {:ok, ttl_seconds} <- parse_ttl(ttl_str),
         {:ok, validated_params} <- validate_secret(value, ttl_seconds),
         {:ok, result} <- create_secret(validated_params, passphrase) do
      {:noreply, push_navigate(socket, to: ~p"/secrets/#{result.key}/created")}
    else
      {:error, :empty_value} ->
        {:noreply, assign(socket, error: "Secret value cannot be empty")}

      {:error, :invalid_ttl} ->
        {:noreply, assign(socket, error: "Invalid expiration time selected")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Failed to create secret: #{inspect(reason)}")}
    end
  end

  defp parse_ttl(ttl_str) do
    case Integer.parse(ttl_str) do
      {ttl, ""} when ttl > 0 -> {:ok, ttl}
      _ -> {:error, :invalid_ttl}
    end
  end

  defp validate_secret(value, ttl_seconds) do
    cond do
      String.trim(value) == "" ->
        {:error, :empty_value}

      ttl_seconds <= 0 ->
        {:error, :invalid_ttl}

      true ->
        {:ok, %{value: value, ttl_seconds: ttl_seconds}}
    end
  end

  defp create_secret(params, passphrase) do
    # For now, create anonymous secrets (no organization_id enforcement)
    # We'll add org context and plan entitlements later with Session App
    attrs = %{
      value: params.value,
      ttl_seconds: params.ttl_seconds,
      # TODO: Replace with actual org from session context
      organization_id: get_default_organization_id()
    }

    opts =
      if passphrase != "" do
        [passphrase: passphrase]
      else
        []
      end

    Secrets.create_secret(attrs, opts)
  end

  defp get_default_organization_id do
    # TEMP: Use first org (free plan) as default until we have sessions
    # This will be replaced with session.active_organization_id
    org = OneTimeSecret.Repo.one(OneTimeSecret.Organizations.Organization)

    if org do
      org.id
    else
      raise "No organizations found! Run: mix run priv/repo/seeds.exs && mix ecto.reset"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <div class="mb-8">
          <h1 class="text-4xl font-bold text-base-content mb-2">Share a Secret</h1>
          <p class="text-base-content/70">
            Create a one-time secret that will be permanently deleted after it's viewed.
          </p>
        </div>

        <.form
          for={@form}
          id="secret-form"
          phx-change="validate"
          phx-submit="create"
          class="space-y-6"
        >
          <div>
            <label for="secret-value" class="block text-sm font-medium text-base-content mb-2">
              Secret Value
            </label>
            <textarea
              id="secret-value"
              name="secret[value]"
              rows="6"
              class="textarea textarea-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
              placeholder="Enter your secret message, password, or sensitive information..."
              required
            >{@form.params["value"]}</textarea>
          </div>

          <div>
            <label for="secret-ttl" class="block text-sm font-medium text-base-content mb-2">
              Expires After
            </label>
            <select
              id="secret-ttl"
              name="secret[ttl_seconds]"
              class="select select-bordered w-full bg-base-100 text-base-content focus:ring-2 focus:ring-primary"
            >
              <%= for {label, seconds} <- @ttl_options do %>
                <option value={seconds} selected={@form.params["ttl_seconds"] == to_string(seconds)}>
                  {label}
                </option>
              <% end %>
            </select>
          </div>

          <div>
            <label for="secret-passphrase" class="block text-sm font-medium text-base-content mb-2">
              Passphrase (Optional)
            </label>
            <input
              type="text"
              id="secret-passphrase"
              name="secret[passphrase]"
              class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary"
              placeholder="Add extra protection with a passphrase"
              value={@form.params["passphrase"]}
            />
            <p class="text-sm text-base-content/60 mt-1">
              If set, the recipient will need this passphrase to view the secret.
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

          <div class="flex gap-3">
            <button type="submit" class="btn btn-primary flex-1" disabled={@creating}>
              <%= if @creating do %>
                <span class="loading loading-spinner"></span> Creating...
              <% else %>
                Create Secret Link
              <% end %>
            </button>
          </div>
        </.form>

        <div class="mt-8 p-4 bg-base-200 rounded-lg">
          <h3 class="font-semibold text-base-content mb-2">How it works</h3>
          <ul class="space-y-2 text-sm text-base-content/80">
            <li class="flex gap-2">
              <span class="text-primary">✓</span>
              <span>Your secret is encrypted before being stored</span>
            </li>
            <li class="flex gap-2">
              <span class="text-primary">✓</span>
              <span>The link works only once—after viewing, the secret is permanently deleted</span>
            </li>
            <li class="flex gap-2">
              <span class="text-primary">✓</span>
              <span>Secrets automatically expire if not viewed within the selected timeframe</span>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
