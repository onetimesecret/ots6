defmodule OneTimeSecret.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :personal, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :plan, OneTimeSecret.Plans.Plan
    belongs_to :owner, OneTimeSecret.Accounts.Account

    has_many :memberships, OneTimeSecret.Organizations.Membership
    has_many :accounts, through: [:memberships, :account]
    has_many :custom_domains, OneTimeSecret.CustomDomains.CustomDomain
    has_many :secret_receipts, OneTimeSecret.Secrets.Receipt

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :personal, :metadata, :plan_id, :owner_id])
    |> validate_required([:name, :slug, :plan_id, :owner_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_length(:slug, min: 2, max: 50)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:plan_id)
    |> foreign_key_constraint(:owner_id)
  end

  @doc """
  Changeset for updating organization metadata.
  """
  def metadata_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:metadata])
    |> validate_required([:metadata])
  end

  @doc """
  Changeset for updating organization name and slug.
  """
  def profile_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_length(:slug, min: 2, max: 50)
    |> unique_constraint(:slug)
  end
end
