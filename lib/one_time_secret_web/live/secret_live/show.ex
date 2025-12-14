defmodule OneTimeSecretWeb.SecretLive.Show do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Secrets

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    case Secrets.get_secret_metadata(key) do
      {:ok, metadata} ->
        {:ok,
         socket
         |> assign(:page_title, "View Secret")
         |> assign(:key, key)
         |> assign(:metadata, metadata)
         |> assign(:passphrase, "")
         |> assign(:revealed, false)
         |> assign(:secret_value, nil)
         |> assign(:error, nil)
         |> assign(:revealing, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:page_title, "Secret Not Found")
         |> assign(:key, key)
         |> assign(:not_found, true)}
    end
  end

  @impl true
  def handle_event("validate_passphrase", %{"passphrase" => passphrase}, socket) do
    {:noreply, assign(socket, passphrase: passphrase, error: nil)}
  end

  @impl true
  def handle_event("reveal", params, socket) do
    passphrase = Map.get(params, "passphrase", "")

    opts =
      if socket.assigns.metadata.passphrase_required && passphrase != "" do
        [passphrase: passphrase]
      else
        []
      end

    socket = assign(socket, revealing: true)

    case Secrets.reveal_secret(socket.assigns.key, opts) do
      {:ok, plaintext} ->
        {:noreply,
         socket
         |> assign(:revealed, true)
         |> assign(:secret_value, plaintext)
         |> assign(:revealing, false)
         |> assign(:error, nil)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:not_found, true)
         |> assign(:revealing, false)}

      {:error, :passphrase_required} ->
        {:noreply,
         socket
         |> assign(:error, "This secret requires a passphrase")
         |> assign(:revealing, false)}

      {:error, :invalid_passphrase} ->
        {:noreply,
         socket
         |> assign(:error, "Incorrect passphrase. Please try again.")
         |> assign(:passphrase, "")
         |> assign(:revealing, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to reveal secret: #{inspect(reason)}")
         |> assign(:revealing, false)}
    end
  end

  @impl true
  def handle_event("copy", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <%= if assigns[:not_found] do %>
          <div class="text-center py-12">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-error/20 mb-4">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-8 w-8 text-error"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </div>
            <h1 class="text-3xl font-bold text-base-content mb-2">Secret Not Found</h1>
            <p class="text-base-content/70 mb-6">
              This secret doesn't exist, has already been viewed, or has expired.
            </p>
            <a href="/" class="btn btn-primary">Create a Secret</a>
          </div>
        <% else %>
          <%= if @revealed do %>
            <div class="mb-8 text-center">
              <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-success/20 mb-4">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-8 w-8 text-success"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                  />
                </svg>
              </div>
              <h1 class="text-4xl font-bold text-base-content mb-2">Secret Revealed</h1>
              <p class="text-base-content/70">
                This secret has been permanently deleted from our servers.
              </p>
            </div>

            <div class="card bg-base-200 shadow-xl mb-6">
              <div class="card-body">
                <h2 class="card-title text-base-content mb-4">Secret Content</h2>

                <div class="relative">
                  <textarea
                    readonly
                    rows="8"
                    class="textarea textarea-bordered w-full bg-base-100 text-base-content font-mono text-sm resize-none"
                    id="secret-content"
                    phx-hook=".CopyToClipboard"
                  >{@secret_value}</textarea>

                  <button
                    type="button"
                    phx-click="copy"
                    class="btn btn-sm btn-ghost absolute top-2 right-2"
                    data-clipboard-target="#secret-content"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-4 w-4"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                      />
                    </svg>
                    Copy
                  </button>
                </div>
              </div>
            </div>

            <div class="alert alert-info mb-6">
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
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>
                This secret cannot be viewed again. It has been permanently deleted.
              </span>
            </div>

            <div class="text-center">
              <a href="/" class="btn btn-primary">Create Another Secret</a>
            </div>
          <% else %>
            <div class="mb-8">
              <h1 class="text-4xl font-bold text-base-content mb-2">You've Received a Secret</h1>
              <p class="text-base-content/70">
                This secret can only be viewed once. After you reveal it, it will be permanently deleted.
              </p>
            </div>

            <div class="card bg-base-200 shadow-xl mb-6">
              <div class="card-body">
                <%= if @metadata.passphrase_required do %>
                  <h2 class="card-title text-base-content mb-4">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-6 w-6 text-warning"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                      />
                    </svg>
                    Passphrase Required
                  </h2>

                  <p class="text-sm text-base-content/70 mb-4">
                    This secret is protected with a passphrase. Enter it below to reveal the secret.
                  </p>

                  <.form for={%{}} phx-submit="reveal" phx-change="validate_passphrase">
                    <input
                      type="password"
                      name="passphrase"
                      value={@passphrase}
                      placeholder="Enter passphrase"
                      class="input input-bordered w-full bg-base-100 text-base-content placeholder:text-base-content/50 focus:ring-2 focus:ring-primary mb-4"
                      autofocus
                      required
                    />

                    <%= if @error do %>
                      <div class="alert alert-error mb-4">
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

                    <button type="submit" class="btn btn-primary w-full" disabled={@revealing}>
                      <%= if @revealing do %>
                        <span class="loading loading-spinner"></span> Revealing...
                      <% else %>
                        Reveal Secret
                      <% end %>
                    </button>
                  </.form>
                <% else %>
                  <h2 class="card-title text-base-content mb-4">Ready to View</h2>

                  <p class="text-sm text-base-content/70 mb-4">
                    Click the button below to reveal the secret. It will be shown only once.
                  </p>

                  <%= if @error do %>
                    <div class="alert alert-error mb-4">
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

                  <button
                    type="button"
                    phx-click="reveal"
                    class="btn btn-primary w-full"
                    disabled={@revealing}
                  >
                    <%= if @revealing do %>
                      <span class="loading loading-spinner"></span> Revealing...
                    <% else %>
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-5 w-5 mr-2"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                        />
                      </svg>
                      Reveal Secret
                    <% end %>
                  </button>
                <% end %>
              </div>
            </div>

            <div class="alert alert-warning">
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
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
              <span>
                Warning: Once revealed, this secret will be permanently deleted and cannot be recovered.
              </span>
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const target = document.querySelector(this.el.dataset.clipboardTarget || this.el);
            if (target) {
              target.select();
              document.execCommand("copy");
            }
          });
        }
      }
    </script>
    """
  end
end
