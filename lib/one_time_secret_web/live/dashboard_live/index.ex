defmodule OneTimeSecretWeb.DashboardLive.Index do
  use OneTimeSecretWeb, :live_view

  on_mount OneTimeSecretWeb.Live.Hooks.RequireAuthenticated

  @impl true
  def mount(_params, _session, socket) do
    # current_account and current_organization come from on_mount hook
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl">
        <div class="mb-8">
          <h1 class="text-4xl font-bold text-base-content mb-2">Dashboard</h1>
          <p class="text-base-content/70">
            Welcome back, {@current_account.email}
          </p>
        </div>

        <div class="grid gap-6">
          <div class="card bg-base-200 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-base-content">Account Information</h2>

              <div class="space-y-3 mt-4">
                <div class="flex justify-between items-center">
                  <span class="text-sm font-medium text-base-content/70">Email</span>
                  <span class="text-base-content">{@current_account.email}</span>
                </div>

                <div class="flex justify-between items-center">
                  <span class="text-sm font-medium text-base-content/70">Display Name</span>
                  <span class="text-base-content">
                    {@current_account.display_name || "Not set"}
                  </span>
                </div>

                <div class="flex justify-between items-center">
                  <span class="text-sm font-medium text-base-content/70">Verified</span>
                  <span class="text-base-content">
                    <span :if={@current_account.email_verified_at} class="badge badge-success">Yes</span>
                    <span :if={!@current_account.email_verified_at} class="badge badge-warning">No</span>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-200 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-base-content">Active Organization</h2>

              <div class="space-y-3 mt-4">
                <div class="flex justify-between items-center">
                  <span class="text-sm font-medium text-base-content/70">Name</span>
                  <span class="text-base-content">{@current_organization.name}</span>
                </div>

                <div class="flex justify-between items-center">
                  <span class="text-sm font-medium text-base-content/70">Type</span>
                  <span class="text-base-content">
                    <span :if={@current_organization.personal} class="badge badge-info">Personal</span>
                    <span :if={!@current_organization.personal} class="badge badge-primary">Team</span>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-3">
            <a href="/" class="btn btn-ghost">Create Secret</a>
            <a href="/logout" data-method="delete" class="btn btn-error">
              Log Out
            </a>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
