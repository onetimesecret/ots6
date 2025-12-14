defmodule OneTimeSecret.Repo.Migrations.CreateCustomDomains do
  use Ecto.Migration

  def change do
    create table(:custom_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hostname, :string, null: false
      add :verified_at, :utc_datetime_usec
      add :verification_token, :string, null: false

      # Branding
      add :brand_name, :string
      add :logo_url, :string
      add :primary_color, :string
      add :custom_css, :text

      # Mode settings
      add :public_homepage, :boolean, null: false, default: false
      add :anonymous_create, :boolean, null: false, default: false
      add :incoming_secrets_email, :string

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_domains, [:hostname])
    create index(:custom_domains, [:organization_id])
    create index(:custom_domains, [:verified_at])
  end
end
