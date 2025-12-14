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
      :secret_key,
      :ttl_seconds,
      :passphrase_required,
      :revealed_at,
      :burned_at,
      :revealed_by_ip,
      :receipt_expires_at,
      :organization_id,
      :custom_domain_id,
      :created_by_id,
      :recipient_id
    ])
    |> validate_required([:secret_key, :ttl_seconds, :receipt_expires_at, :organization_id])
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:custom_domain_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:recipient_id)
  end

  @doc """
  Changeset for marking a secret as revealed.
  """
  def reveal_changeset(receipt, ip_address) do
    receipt
    |> change(revealed_at: DateTime.utc_now(), revealed_by_ip: ip_address)
  end

  @doc """
  Changeset for marking a secret as burned (destroyed before reveal).
  """
  def burn_changeset(receipt) do
    receipt
    |> change(burned_at: DateTime.utc_now())
  end

  @doc """
  Helper to calculate receipt expiry (2x the secret TTL).
  """
  def calculate_receipt_expires_at(created_at, ttl_seconds) do
    DateTime.add(created_at, ttl_seconds * 2, :second)
  end
end
