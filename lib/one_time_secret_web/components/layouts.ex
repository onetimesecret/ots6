defmodule OneTimeSecretWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OneTimeSecretWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen">
      <header class="border-b border-base-300 bg-base-100" role="banner">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex items-center justify-between">
            <nav aria-label="Main navigation">
              <a href="/" class="inline-flex items-center gap-3 hover:opacity-80 transition-opacity">
                <svg
                  width="32"
                  height="32"
                  viewBox="0 0 100 100"
                  fill="none"
                  xmlns="http://www.w3.org/2000/svg"
                  aria-hidden="true"
                >
                  <circle cx="50" cy="50" r="45" fill="currentColor" class="text-primary" />
                  <path
                    d="M50 20 L65 40 L50 35 L35 40 Z"
                    fill="currentColor"
                    class="text-primary-content"
                  />
                  <rect
                    x="45"
                    y="40"
                    width="10"
                    height="40"
                    fill="currentColor"
                    class="text-primary-content"
                  />
                  <circle cx="50" cy="65" r="8" fill="currentColor" class="text-base-100" />
                </svg>
                <span class="text-xl font-semibold text-base-content">OneTimeSecret</span>
              </a>
            </nav>

            <div class="flex items-center gap-4">
              <a href="/login" class="btn btn-ghost btn-sm">Log In</a>
              <a href="/register" class="btn btn-primary btn-sm">Sign Up</a>
            </div>
          </div>
        </div>
      </header>

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8" role="main" id="main-content" tabindex="-1">
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-base-300 bg-base-100 mt-auto" role="contentinfo">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div class="flex flex-col sm:flex-row justify-between items-center gap-4">
            <p class="text-sm text-base-content/70">
              © 2024 OneTimeSecret. Share secrets securely.
            </p>
            <.theme_toggle />
          </div>
        </div>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" aria-atomic="true">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-2" role="group" aria-label="Theme selector">
      <span class="text-sm text-base-content/70" id="theme-label">Theme:</span>
      <div
        class="btn-group"
        role="radiogroup"
        aria-labelledby="theme-label"
      >
        <button
          type="button"
          phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "light"}, bubbles: true)}
          class="btn btn-sm btn-ghost"
          aria-label="Light theme"
          role="radio"
          aria-checked="false"
        >
          <.icon name="hero-sun" class="size-4" />
        </button>

        <button
          type="button"
          phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "dark"}, bubbles: true)}
          class="btn btn-sm btn-ghost"
          aria-label="Dark theme"
          role="radio"
          aria-checked="false"
        >
          <.icon name="hero-moon" class="size-4" />
        </button>

        <button
          type="button"
          phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "high-contrast"}, bubbles: true)}
          class="btn btn-sm btn-ghost"
          aria-label="High contrast theme"
          role="radio"
          aria-checked="false"
        >
          <.icon name="hero-eye" class="size-4" />
        </button>

        <button
          type="button"
          phx-click={JS.dispatch("phx:set-theme", detail: %{theme: "smooth-jazz"}, bubbles: true)}
          class="btn btn-sm btn-ghost"
          aria-label="Smooth jazz theme"
          role="radio"
          aria-checked="false"
        >
          <.icon name="hero-musical-note" class="size-4" />
        </button>
      </div>
    </div>
    """
  end
end
