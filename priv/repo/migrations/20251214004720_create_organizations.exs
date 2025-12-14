defmodule OneTimeSecret.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :personal, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      add :plan_id, references(:plans, type: :binary_id, on_delete: :restrict), null: false
      add :owner_id, references(:accounts, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])
    create index(:organizations, [:plan_id])
    create index(:organizations, [:owner_id])
    create index(:organizations, [:personal])
  end
end
