defmodule OneTimeSecret.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false

      # Limits
      add :max_secret_size_bytes, :integer, null: false
      add :max_ttl_seconds, :integer, null: false
      add :max_secrets_per_day, :integer
      add :max_custom_domains, :integer, null: false, default: 0
      add :max_members, :integer

      # Feature flags
      add :custom_branding, :boolean, null: false, default: false
      add :member_auth_on_custom_domain, :boolean, null: false, default: false
      add :admin_on_custom_domain, :boolean, null: false, default: false
      add :member_to_member_sharing, :boolean, null: false, default: false
      add :incoming_secrets, :boolean, null: false, default: false
      add :api_access, :boolean, null: false, default: false
      add :sso_enabled, :boolean, null: false, default: false
      add :audit_log, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plans, [:slug])
  end
end
