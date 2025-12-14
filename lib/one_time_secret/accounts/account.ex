defmodule OneTimeSecret.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :email, :string
    field :email_verified_at, :utc_datetime_usec
    field :password_hash, :string
    field :password, :string, virtual: true, redact: true
    field :totp_secret, :string
    field :display_name, :string
    field :locale, :string, default: "en"
    field :timezone, :string

    has_many :memberships, OneTimeSecret.Organizations.Membership
    has_many :organizations, through: [:memberships, :organization]
    has_many :sessions, OneTimeSecret.Sessions.Session
    has_many :created_receipts, OneTimeSecret.Secrets.Receipt, foreign_key: :created_by_id
    has_many :received_receipts, OneTimeSecret.Secrets.Receipt, foreign_key: :recipient_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :password, :display_name, :locale, :timezone])
    |> validate_required([:email])
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
  end

  @doc false
  def email_changeset(account, attrs) do
    account
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email()
    |> prepare_changes(&set_email_verification_pending/1)
  end

  @doc false
  def password_changeset(account, attrs) do
    account
    |> cast(attrs, [:password])
    |> validate_password()
    |> put_password_hash()
  end

  @doc false
  def profile_changeset(account, attrs) do
    account
    |> cast(attrs, [:display_name, :locale, :timezone])
    |> validate_length(:display_name, max: 100)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, OneTimeSecret.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
  end

  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      _ ->
        changeset
    end
  end

  defp set_email_verification_pending(changeset) do
    put_change(changeset, :email_verified_at, nil)
  end
end
