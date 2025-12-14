defmodule OneTimeSecret.Organizations.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :member], default: :member
    field :provisioned_via, Ecto.Enum, values: [:invite, :sso, :scim], default: :invite
    field :joined_at, :utc_datetime_usec

    belongs_to :account, OneTimeSecret.Accounts.Account
    belongs_to :organization, OneTimeSecret.Organizations.Organization
    belongs_to :domain_scope, OneTimeSecret.CustomDomains.CustomDomain

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :role,
      :provisioned_via,
      :joined_at,
      :account_id,
      :organization_id,
      :domain_scope_id
    ])
    |> validate_required([:role, :provisioned_via, :account_id, :organization_id])
    |> put_joined_at()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:domain_scope_id)
    |> unique_constraint([:account_id, :organization_id])
  end

  @doc """
  Changeset for updating a membership's role.
  """
  def role_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc """
  Changeset for setting domain scope on a membership.
  """
  def domain_scope_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:domain_scope_id])
    |> foreign_key_constraint(:domain_scope_id)
  end

  defp put_joined_at(changeset) do
    case get_field(changeset, :joined_at) do
      nil -> put_change(changeset, :joined_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
