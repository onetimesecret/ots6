# Ecto Schemas & PostgreSQL Data Models

## Overview

PostgreSQL stores all durable, relational data. Redis handles ephemeral secrets. This document defines the Ecto schemas, associations, constraints, and indexes for the core domain models.

---

## Schema Conventions

**Primary Keys:**
- UUIDs (`:binary_id`) for all tables
- Generated via `Ecto.UUID.generate()` on insert

**Timestamps:**
- All schemas use `timestamps(type: :utc_datetime_usec)`
- Provides `inserted_at` and `updated_at` automatically

**Foreign Keys:**
- Always include `ON DELETE` constraints
- Most are `ON DELETE CASCADE` or `ON DELETE RESTRICT` based on business logic

**Indexes:**
- Unique constraints on business keys (email, slug, hostname)
- Foreign key indexes for join performance
- Composite indexes for common query patterns
- BRIN indexes on timestamp columns for time-series queries

---

## Account Schema

The identity. One human, one account.

```elixir
defmodule OneTimeSecret.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :email, :string
    field :email_verified_at, :utc_datetime_usec
    field :password_hash, :string
    field :totp_secret, :string
    field :display_name, :string
    field :locale, :string, default: "en"
    field :timezone, :string

    has_many :memberships, OneTimeSecret.Organizations.Membership
    has_many :organizations, through: [:memberships, :organization]
    has_many :sessions, OneTimeSecret.Sessions.Session
    has_many :api_tokens, OneTimeSecret.API.Token

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :password, :display_name, :locale, :timezone])
    |> validate_required([:email])
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
  end

  @doc false
  def email_changeset(account, attrs) do
    account
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email()
    |> prepare_changes(&set_email_verification_pending/1)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, OneTimeSecret.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
  end

  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
      _ ->
        changeset
    end
  end

  defp set_email_verification_pending(changeset) do
    put_change(changeset, :email_verified_at, nil)
  end
end
```

**Migration:**

```elixir
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
```

---

## Plan Schema

Defines entitlements for organizations.

```elixir
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
      :name, :slug,
      :max_secret_size_bytes, :max_ttl_seconds, :max_secrets_per_day,
      :max_custom_domains, :max_members,
      :custom_branding, :member_auth_on_custom_domain, :admin_on_custom_domain,
      :member_to_member_sharing, :incoming_secrets, :api_access,
      :sso_enabled, :audit_log
    ])
    |> validate_required([:name, :slug, :max_secret_size_bytes, :max_ttl_seconds])
    |> validate_number(:max_secret_size_bytes, greater_than: 0)
    |> validate_number(:max_ttl_seconds, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
```

**Migration:**

```elixir
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
```

---

## Organization Schema

The billing and entitlement holder.

```elixir
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
end
```

**Migration:**

```elixir
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
```

---

## Membership Schema

Connects accounts to organizations with role and optional domain scoping.

```elixir
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
    |> cast(attrs, [:role, :provisioned_via, :joined_at, :account_id, :organization_id, :domain_scope_id])
    |> validate_required([:role, :provisioned_via, :account_id, :organization_id])
    |> put_joined_at()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:domain_scope_id)
    |> unique_constraint([:account_id, :organization_id])
  end

  defp put_joined_at(changeset) do
    case get_field(changeset, :joined_at) do
      nil -> put_change(changeset, :joined_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
```

**Migration:**

```elixir
defmodule OneTimeSecret.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "member"
      add :provisioned_via, :string, null: false, default: "invite"
      add :joined_at, :utc_datetime_usec, null: false
      
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :domain_scope_id, references(:custom_domains, type: :binary_id, on_delete: :set_null)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:account_id, :organization_id])
    create index(:memberships, [:organization_id])
    create index(:memberships, [:domain_scope_id])
    create index(:memberships, [:role])
  end
end
```

**Domain Scope Constraint:**

The `domain_scope_id` foreign key references `custom_domains` which doesn't exist yet at migration time. We'll create this migration after `custom_domains` is created, or use a forward reference with `references(:custom_domains, ...)` and ensure migration order is correct.

---

## CustomDomain Schema

A branded entry point to the platform.

```elixir
defmodule OneTimeSecret.CustomDomains.CustomDomain do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "custom_domains" do
    field :hostname, :string
    field :verified_at, :utc_datetime_usec
    field :verification_token, :string
    
    # Branding
    field :brand_name, :string
    field :logo_url, :string
    field :primary_color, :string
    field :custom_css, :string
    
    # Mode settings
    field :public_homepage, :boolean, default: false
    field :anonymous_create, :boolean, default: false
    field :incoming_secrets_email, :string

    belongs_to :organization, OneTimeSecret.Organizations.Organization

    has_many :memberships, OneTimeSecret.Organizations.Membership, foreign_key: :domain_scope_id
    has_many :secret_receipts, OneTimeSecret.Secrets.Receipt

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(custom_domain, attrs) do
    custom_domain
    |> cast(attrs, [
      :hostname, :brand_name, :logo_url, :primary_color, :custom_css,
      :public_homepage, :anonymous_create, :incoming_secrets_email,
      :organization_id
    ])
    |> validate_required([:hostname, :organization_id])
    |> validate_hostname()
    |> put_verification_token()
    |> unique_constraint(:hostname)
    |> foreign_key_constraint(:organization_id)
  end

  @doc false
  def verification_changeset(custom_domain, verified \\ true) do
    if verified do
      change(custom_domain, verified_at: DateTime.utc_now())
    else
      change(custom_domain, verified_at: nil)
    end
  end

  defp validate_hostname(changeset) do
    changeset
    |> validate_format(:hostname, ~r/^[a-z0-9\-\.]+$/)
    |> validate_length(:hostname, min: 3, max: 253)
  end

  defp put_verification_token(changeset) do
    case get_field(changeset, :verification_token) do
      nil -> 
        token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        put_change(changeset, :verification_token, token)
      _ -> 
        changeset
    end
  end
end
```

**Migration:**

```elixir
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
      
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_domains, [:hostname])
    create index(:custom_domains, [:organization_id])
    create index(:custom_domains, [:verified_at])
  end
end
```

---

## Secret Receipt Schema

The durable audit record. Survives 2x the original TTL.

```elixir
defmodule OneTimeSecret.Secrets.Receipt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "secret_receipts" do
    field :secret_key, :string
    field :ttl_seconds, :integer
    field :passphrase_required, :boolean, default: false
    field :revealed_at, :utc_datetime_usec
    field :burned_at, :utc_datetime_usec
    field :revealed_by_ip, :string
    field :receipt_expires_at, :utc_datetime_usec

    belongs_to :organization, OneTimeSecret.Organizations.Organization
    belongs_to :custom_domain, OneTimeSecret.CustomDomains.CustomDomain
    belongs_to :created_by, OneTimeSecret.Accounts.Account
    belongs_to :recipient, OneTimeSecret.Accounts.Account

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :secret_key, :ttl_seconds, :passphrase_required,
      :revealed_at, :burned_at, :revealed_by_ip, :receipt_expires_at,
      :organization_id, :custom_domain_id, :created_by_id, :recipient_id
    ])
    |> validate_required([:secret_key, :ttl_seconds, :receipt_expires_at, :organization_id])
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:custom_domain_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:recipient_id)
  end

  @doc false
  def reveal_changeset(receipt, ip_address) do
    receipt
    |> change(revealed_at: DateTime.utc_now(), revealed_by_ip: ip_address)
  end

  @doc false
  def burn_changeset(receipt) do
    receipt
    |> change(burned_at: DateTime.utc_now())
  end
end
```

**Migration:**

```elixir
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
      
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :custom_domain_id, references(:custom_domains, type: :binary_id, on_delete: :set_null)
      add :created_by_id, references(:accounts, type: :binary_id, on_delete: :set_null)
      add :recipient_id, references(:accounts, type: :binary_id, on_delete: :set_null)

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
    execute "CREATE INDEX secret_receipts_inserted_at_brin_idx ON secret_receipts USING BRIN (inserted_at)"
  end
end
```

---

## Session Schema

Tracks authenticated state and active context.

```elixir
defmodule OneTimeSecret.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :context_type, Ecto.Enum, values: [:canonical, :custom_domain]
    field :ip_address, :string
    field :user_agent, :string
    field :expires_at, :utc_datetime_usec
    field :last_active_at, :utc_datetime_usec

    belongs_to :account, OneTimeSecret.Accounts.Account
    belongs_to :custom_domain, OneTimeSecret.CustomDomains.CustomDomain
    belongs_to :active_organization, OneTimeSecret.Organizations.Organization
    belongs_to :active_custom_domain, OneTimeSecret.CustomDomains.CustomDomain

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :context_type, :ip_address, :user_agent, :expires_at,
      :account_id, :custom_domain_id, :active_organization_id, :active_custom_domain_id
    ])
    |> validate_required([:context_type, :account_id, :active_organization_id])
    |> put_default_expiry()
    |> put_last_active()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:custom_domain_id)
    |> foreign_key_constraint(:active_organization_id)
    |> foreign_key_constraint(:active_custom_domain_id)
  end

  defp put_default_expiry(changeset) do
    case get_field(changeset, :expires_at) do
      nil ->
        # 7 day default TTL
        expires_at = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)
        put_change(changeset, :expires_at, expires_at)
      _ ->
        changeset
    end
  end

  defp put_last_active(changeset) do
    put_change(changeset, :last_active_at, DateTime.utc_now())
  end
end
```

**Migration:**

```elixir
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
      
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :custom_domain_id, references(:custom_domains, type: :binary_id, on_delete: :delete_all)
      add :active_organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :active_custom_domain_id, references(:custom_domains, type: :binary_id, on_delete: :set_null)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:account_id])
    create index(:sessions, [:custom_domain_id])
    create index(:sessions, [:active_organization_id])
    create index(:sessions, [:expires_at])
  end
end
```

---

## Migration Order

To satisfy foreign key constraints, migrations must be created in this order:

1. `plans`
2. `accounts`
3. `organizations` (references plans, accounts)
4. `custom_domains` (references organizations)
5. `memberships` (references accounts, organizations, custom_domains)
6. `secret_receipts` (references organizations, custom_domains, accounts)
7. `sessions` (references accounts, custom_domains, organizations)

---

## Personal Organization Auto-Creation

The implicit personal org is created via `Ecto.Multi` in application logic:

```elixir
defmodule OneTimeSecret.Accounts do
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Accounts.Account
  alias OneTimeSecret.Organizations.{Organization, Membership}
  alias OneTimeSecret.Plans

  def register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:account, Account.registration_changeset(%Account{}, attrs))
    |> Ecto.Multi.run(:personal_org, fn repo, %{account: account} ->
      free_plan = Plans.get_plan_by_slug!("free")
      
      org_attrs = %{
        name: "#{account.email}'s Workspace",
        slug: generate_slug(account.email),
        personal: true,
        plan_id: free_plan.id,
        owner_id: account.id
      }
      
      %Organization{}
      |> Organization.changeset(org_attrs)
      |> repo.insert()
    end)
    |> Ecto.Multi.insert(:owner_membership, fn %{account: account, personal_org: org} ->
      %Membership{}
      |> Membership.changeset(%{
        account_id: account.id,
        organization_id: org.id,
        role: :owner,
        provisioned_via: :invite
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{account: account}} -> {:ok, account}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  defp generate_slug(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> Kernel.<>("-#{:rand.uniform(9999)}")
  end
end
```

This ensures atomicity—either all three records are created, or none are.

---

## Summary

**PostgreSQL stores:**
- Accounts, organizations, memberships, plans
- Custom domains (verification, branding config)
- Secret receipts (audit trail, 2x TTL)
- Sessions (authenticated state tracking)

**Redis stores:**
- Secrets (encrypted payload, auto-expiring)
- Timelines (sorted sets for efficient iteration)
- Passphrase attempt counters

**Next:** Redis wrapper modules implementing the Familia pattern.

