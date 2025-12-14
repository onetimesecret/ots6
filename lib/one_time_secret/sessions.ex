defmodule OneTimeSecret.Sessions do
  @moduledoc """
  The Sessions context.

  Manages authenticated session lifecycle: create, validate, terminate.
  Sessions are domain-scoped (canonical vs custom_domain) but this initial
  implementation focuses on canonical context only.
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Sessions.Session
  alias OneTimeSecret.Accounts.Account
  alias OneTimeSecret.Organizations

  @session_cookie_key "_one_time_secret_session"
  @session_cookie_opts [
    sign: true,
    max_age: 7 * 24 * 60 * 60,
    same_site: "Lax",
    http_only: true
  ]

  @doc """
  Returns the session cookie key.

  ## Examples

      iex> Sessions.session_cookie_key()
      "_one_time_secret_session"

  """
  def session_cookie_key, do: @session_cookie_key

  @doc """
  Returns the session cookie options.

  ## Examples

      iex> Sessions.session_cookie_opts()
      [sign: true, max_age: 604800, same_site: "Lax", http_only: true]

  """
  def session_cookie_opts, do: @session_cookie_opts

  @doc """
  Creates a new session for an account in canonical context.

  Automatically selects the first organization membership as the active organization.

  ## Parameters

    * `account` - The authenticated account
    * `attrs` - Map with optional keys:
      - `:ip_address` - Client IP address
      - `:user_agent` - Client user agent string

  ## Returns

  `{:ok, session}` on success.
  `{:error, changeset}` on failure.
  `{:error, :no_organizations}` if account has no memberships.

  ## Examples

      iex> create_session(account, %{ip_address: "127.0.0.1"})
      {:ok, %Session{}}

  """
  def create_session(%Account{} = account, attrs \\ %{}) do
    # Get account's first organization (for now - later we'll add org selection)
    organizations = Organizations.list_organizations_for_account(account.id)

    case organizations do
      [] ->
        {:error, :no_organizations}

      [first_org | _] ->
        session_attrs =
          attrs
          |> Map.put(:account_id, account.id)
          |> Map.put(:context_type, :canonical)
          |> Map.put(:active_organization_id, first_org.id)

        %Session{}
        |> Session.changeset(session_attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.

  ## Examples

      iex> get_session!(session_id)
      %Session{}

      iex> get_session!("nonexistent")
      ** (Ecto.NoResultsError)

  """
  def get_session!(id) do
    Repo.get!(Session, id)
    |> Repo.preload([:account, :active_organization])
  end

  @doc """
  Gets a session by ID, preloading associations.

  Returns `nil` if session doesn't exist.

  ## Examples

      iex> get_session(session_id)
      %Session{account: %Account{}, active_organization: %Organization{}}

      iex> get_session("nonexistent")
      nil

  """
  def get_session(id) when is_binary(id) do
    Repo.get(Session, id)
    |> case do
      nil -> nil
      session -> Repo.preload(session, [:account, :active_organization])
    end
  end

  @doc """
  Validates a session and updates last_active_at if valid.

  A session is valid if:
  - It exists
  - It hasn't expired (`expires_at` is in the future)

  If valid, updates `last_active_at` to now and returns the session.

  ## Returns

  `{:ok, session}` if valid and updated.
  `{:error, :expired}` if session exists but expired.
  `{:error, :not_found}` if session doesn't exist.

  ## Examples

      iex> validate_session(session_id)
      {:ok, %Session{}}

      iex> validate_session(expired_session_id)
      {:error, :expired}

  """
  def validate_session(session_id) when is_binary(session_id) do
    case get_session(session_id) do
      nil ->
        {:error, :not_found}

      session ->
        now = DateTime.utc_now()

        cond do
          DateTime.compare(session.expires_at, now) == :lt ->
            # Session expired - terminate it
            terminate_session(session)
            {:error, :expired}

          true ->
            # Valid - touch last_active_at and return
            session
            |> Session.touch_changeset()
            |> Repo.update()
        end
    end
  end

  @doc """
  Terminates a session by deleting it from the database.

  ## Examples

      iex> terminate_session(session)
      {:ok, %Session{}}

      iex> terminate_session(session)
      {:error, %Ecto.Changeset{}}

  """
  def terminate_session(%Session{} = session) do
    Repo.delete(session)
  end

  @doc """
  Terminates a session by ID.

  Returns `{:ok, session}` if found and deleted.
  Returns `{:error, :not_found}` if session doesn't exist.

  ## Examples

      iex> terminate_session(session_id)
      {:ok, %Session{}}

      iex> terminate_session("nonexistent")
      {:error, :not_found}

  """
  def terminate_session(session_id) when is_binary(session_id) do
    case get_session(session_id) do
      nil -> {:error, :not_found}
      session -> terminate_session(session)
    end
  end

  @doc """
  Cleans up expired sessions from the database.

  Deletes all sessions where `expires_at` is in the past.

  Returns the number of sessions deleted.

  ## Examples

      iex> cleanup_expired_sessions()
      {5, nil}

  """
  def cleanup_expired_sessions do
    now = DateTime.utc_now()

    Repo.delete_all(
      from s in Session,
        where: s.expires_at < ^now
    )
  end
end
