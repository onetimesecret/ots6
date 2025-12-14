defmodule OneTimeSecretWeb.SecretLive.Created do
  use OneTimeSecretWeb, :live_view

  alias OneTimeSecret.Secrets

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    case Secrets.get_secret_metadata(key) do
      {:ok, metadata} ->
        base_url = OneTimeSecretWeb.Endpoint.url()
        secret_url = "#{base_url}/secret/#{key}"

        {:ok,
         socket
         |> assign(:page_title, "Secret Created")
         |> assign(:key, key)
         |> assign(:secret_url, secret_url)
         |> assign(:metadata, metadata)
         |> assign(:copied, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Secret not found or has expired")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("copy", _params, socket) do
    {:noreply, assign(socket, copied: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl">
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
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <h1 class="text-4xl font-bold text-base-content mb-2">Secret Created!</h1>
          <p class="text-base-content/70">
            Share this link with your recipient. It can only be viewed once.
          </p>
        </div>

        <div class="card bg-base-200 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-base-content mb-4">Shareable Link</h2>

            <div class="flex gap-2">
              <input
                type="text"
                readonly
                value={@secret_url}
                class="input input-bordered flex-1 bg-base-100 text-base-content font-mono text-sm"
                id="secret-url-input"
                phx-hook=".CopyToClipboard"
              />
              <button
                type="button"
                phx-click="copy"
                class="btn btn-primary"
                data-clipboard-target="#secret-url-input"
              >
                <%= if @copied do %>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  Copied!
                <% else %>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5"
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
                <% end %>
              </button>
            </div>

            <div class="mt-6 space-y-3">
              <div class="flex items-center gap-3 text-sm">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5 text-base-content/60"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span class="text-base-content/80">
                  Expires in <strong class="text-base-content">{format_ttl(@metadata.ttl)}</strong>
                </span>
              </div>

              <%= if @metadata.passphrase_required do %>
                <div class="flex items-center gap-3 text-sm">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5 text-warning"
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
                  <span class="text-base-content/80">
                    <strong class="text-warning">Passphrase required</strong>
                    – Make sure to share it separately
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <div class="alert alert-warning mb-6">
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
            This link will only work <strong>once</strong>. After your recipient views it, the secret will be permanently deleted.
          </span>
        </div>

        <div class="text-center">
          <a href="/" class="btn btn-ghost">Create Another Secret</a>
        </div>
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

  defp format_ttl(seconds) when seconds < 60, do: "#{seconds} seconds"
  defp format_ttl(seconds) when seconds < 3600, do: "#{div(seconds, 60)} minutes"
  defp format_ttl(seconds) when seconds < 86400, do: "#{div(seconds, 3600)} hours"
  defp format_ttl(seconds), do: "#{div(seconds, 86400)} days"
end
