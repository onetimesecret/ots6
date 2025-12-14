defmodule OneTimeSecret.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :email_verified_at, :utc_datetime_usec
      add :password_hash, :string
      add :totp_secret, :string
      add :display_name, :string
      add :locale, :string, null: false, default: "en"
      add :timezone, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:email])
    create index(:accounts, [:email_verified_at])
  end
end
