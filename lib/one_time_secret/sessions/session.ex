defmodule OneTimeSecret.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :context_type, Ecto.Enum, values: [:canonical, :custom_domain]
    field :ip_address, :string
    field :user_agent, :string
    field :expires_at, :utc_datetime_usec
    field :last_active_at, :utc_datetime_usec

    belongs_to :account, OneTimeSecret.Accounts.Account
    belongs_to :custom_domain, OneTimeSecret.CustomDomains.CustomDomain
    belongs_to :active_organization, OneTimeSecret.Organizations.Organization
    belongs_to :active_custom_domain, OneTimeSecret.CustomDomains.CustomDomain

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :context_type,
      :ip_address,
      :user_agent,
      :expires_at,
      :account_id,
      :custom_domain_id,
      :active_organization_id,
      :active_custom_domain_id
    ])
    |> validate_required([:context_type, :account_id, :active_organization_id])
    |> put_default_expiry()
    |> put_last_active()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:custom_domain_id)
    |> foreign_key_constraint(:active_organization_id)
    |> foreign_key_constraint(:active_custom_domain_id)
  end

  @doc """
  Changeset for updating session activity timestamp.
  """
  def touch_changeset(session) do
    change(session, last_active_at: DateTime.utc_now())
  end

  defp put_default_expiry(changeset) do
    case get_field(changeset, :expires_at) do
      nil ->
        # 7 day default TTL
        expires_at = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)
        put_change(changeset, :expires_at, expires_at)

      _ ->
        changeset
    end
  end

  defp put_last_active(changeset) do
    put_change(changeset, :last_active_at, DateTime.utc_now())
  end
end
