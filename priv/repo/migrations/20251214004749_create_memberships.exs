defmodule OneTimeSecret.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "member"
      add :provisioned_via, :string, null: false, default: "invite"
      add :joined_at, :utc_datetime_usec, null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :domain_scope_id, references(:custom_domains, type: :binary_id, on_delete: :set_null)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:account_id, :organization_id])
    create index(:memberships, [:organization_id])
    create index(:memberships, [:domain_scope_id])
    create index(:memberships, [:role])
  end
end
