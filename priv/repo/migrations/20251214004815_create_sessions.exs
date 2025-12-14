defmodule OneTimeSecret.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :context_type, :string, null: false
      add :ip_address, :string
      add :user_agent, :string
      add :expires_at, :utc_datetime_usec, null: false
      add :last_active_at, :utc_datetime_usec, null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :custom_domain_id, references(:custom_domains, type: :binary_id, on_delete: :delete_all)

      add :active_organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :active_custom_domain_id,
          references(:custom_domains, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:account_id])
    create index(:sessions, [:custom_domain_id])
    create index(:sessions, [:active_organization_id])
    create index(:sessions, [:expires_at])
  end
end
