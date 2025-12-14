defmodule OneTimeSecret.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Accounts.Account

  @doc """
  Gets a single account.

  Raises `Ecto.NoResultsError` if the Account does not exist.

  ## Examples

      iex> get_account!(123)
      %Account{}

      iex> get_account!(456)
      ** (Ecto.NoResultsError)

  """
  def get_account!(id), do: Repo.get!(Account, id)

  @doc """
  Gets an account by email (case-insensitive).

  Returns `nil` if no account exists with that email.

  ## Examples

      iex> get_account_by_email("[email protected]")
      %Account{}

      iex> get_account_by_email("[email protected]")
      nil

  """
  def get_account_by_email(email) when is_binary(email) do
    normalized_email = String.downcase(email)
    Repo.one(from a in Account, where: fragment("lower(?)", a.email) == ^normalized_email)
  end

  @doc """
  Registers a new account.

  ## Examples

      iex> register_account(%{email: "[email protected]", password: "supersecret123456"})
      {:ok, %Account{}}

      iex> register_account(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def register_account(attrs) do
    %Account{}
    |> Account.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Authenticates an account by email and password.

  Returns `{:ok, account}` if credentials are valid.
  Returns `{:error, :invalid_credentials}` if email doesn't exist or password is wrong.

  Uses timing-safe verification to prevent timing attacks.

  ## Examples

      iex> authenticate_account("[email protected]", "correct_password")
      {:ok, %Account{}}

      iex> authenticate_account("[email protected]", "wrong_password")
      {:error, :invalid_credentials}

      iex> authenticate_account("[email protected]", "any_password")
      {:error, :invalid_credentials}

  """
  def authenticate_account(email, password)
      when is_binary(email) and is_binary(password) do
    account = get_account_by_email(email)

    cond do
      account && account.password_hash && Argon2.verify_pass(password, account.password_hash) ->
        {:ok, account}

      account ->
        # Account exists but password verification failed
        {:error, :invalid_credentials}

      true ->
        # No account found - use no_user_verify to prevent timing attacks
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Returns a changeset for tracking account registration changes.

  ## Examples

      iex> change_account_registration(account)
      %Ecto.}}

  """
  def change_account_registration(%Account{} = account, attrs \\ %{}) do
    Account.registration_changeset(account, attrs)
  end

  @doc """
  Updates an account's profile (display name, locale, timezone).

  ## Examples

      iex> update_account_profile(account, %{display_name: "New Name"})
      {:ok, %Account{}}

      iex> update_account_profile(account, %{display_name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_account_profile(%Account{} = account, attrs) do
    account
    |> Account.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates an account's password after verifying the current password.

  ## Examples

      iex> update_account_password(account, "current_pass", %{password: "new_pass_123456"})
      {:ok, %Account{}}

      iex> update_account_password(account, "wrong_pass", %{password: "new_pass_123456"})
      {:error, :invalid_current_password}

  """
  def update_account_password(%Account{} = account, current_password, attrs)
      when is_binary(current_password) do
    if account.password_hash && Argon2.verify_pass(current_password, account.password_hash) do
      account
      |> Account.password_changeset(attrs)
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  @doc """
  Updates an account's email address.

  Sets `email_verified_at` to nil, requiring re-verification.

  ## Examples

      iex> update_account_email(account, %{email: "[email protected]"})
      {:ok, %Account{}}

  """
  def update_account_email(%Account{} = account, attrs) do
    account
    |> Account.email_changeset(attrs)
    |> Repo.update()
  end
end
