defmodule OneTimeSecret.Repo.Migrations.CreateSecretReceipts do
  use Ecto.Migration

  def change do
    create table(:secret_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :secret_key, :string, null: false
      add :ttl_seconds, :integer, null: false
      add :passphrase_required, :boolean, null: false, default: false
      add :revealed_at, :utc_datetime_usec
      add :burned_at, :utc_datetime_usec
      add :revealed_by_ip, :string
      add :receipt_expires_at, :utc_datetime_usec, null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :custom_domain_id, references(:custom_domains, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :recipient_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:secret_receipts, [:secret_key])
    create index(:secret_receipts, [:organization_id])
    create index(:secret_receipts, [:custom_domain_id])
    create index(:secret_receipts, [:created_by_id])
    create index(:secret_receipts, [:recipient_id])
    create index(:secret_receipts, [:revealed_at])
    create index(:secret_receipts, [:receipt_expires_at])

    # BRIN index for time-series queries on inserted_at
    execute "CREATE INDEX secret_receipts_inserted_at_brin_idx ON secret_receipts USING BRIN (inserted_at)",
            "DROP INDEX secret_receipts_inserted_at_brin_idx"
  end
end
