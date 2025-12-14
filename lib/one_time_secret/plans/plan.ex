defmodule OneTimeSecret.Plans.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plans" do
    field :name, :string
    field :slug, :string

    # Limits
    field :max_secret_size_bytes, :integer
    field :max_ttl_seconds, :integer
    field :max_secrets_per_day, :integer
    field :max_custom_domains, :integer, default: 0
    field :max_members, :integer

    # Feature flags
    field :custom_branding, :boolean, default: false
    field :member_auth_on_custom_domain, :boolean, default: false
    field :admin_on_custom_domain, :boolean, default: false
    field :member_to_member_sharing, :boolean, default: false
    field :incoming_secrets, :boolean, default: false
    field :api_access, :boolean, default: false
    field :sso_enabled, :boolean, default: false
    field :audit_log, :boolean, default: false

    has_many :organizations, OneTimeSecret.Organizations.Organization

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :slug,
      :max_secret_size_bytes,
      :max_ttl_seconds,
      :max_secrets_per_day,
      :max_custom_domains,
      :max_members,
      :custom_branding,
      :member_auth_on_custom_domain,
      :admin_on_custom_domain,
      :member_to_member_sharing,
      :incoming_secrets,
      :api_access,
      :sso_enabled,
      :audit_log
    ])
    |> validate_required([:name, :slug, :max_secret_size_bytes, :max_ttl_seconds])
    |> validate_number(:max_secret_size_bytes, greater_than: 0)
    |> validate_number(:max_ttl_seconds, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
