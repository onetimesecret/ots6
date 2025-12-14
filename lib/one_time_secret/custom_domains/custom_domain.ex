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

    # Extended branding
    field :colour, :string
    field :instructions_pre_reveal, :string
    field :instructions_reveal, :string
    field :instructions_post_reveal, :string
    field :description, :string
    field :button_text_light, :string
    field :allow_public_homepage, :boolean, default: false
    field :allow_public_api, :boolean, default: false
    field :font_family, :string
    field :corner_style, :string
    field :locale, :string

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
      :hostname,
      :brand_name,
      :logo_url,
      :primary_color,
      :custom_css,
      :public_homepage,
      :anonymous_create,
      :incoming_secrets_email,
      :organization_id
    ])
    |> validate_required([:hostname, :organization_id])
    |> validate_hostname()
    |> put_verification_token()
    |> unique_constraint(:hostname)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Changeset for marking a domain as verified or unverified.
  """
  def verification_changeset(custom_domain, verified \\ true) do
    if verified do
      change(custom_domain, verified_at: DateTime.utc_now())
    else
      change(custom_domain, verified_at: nil)
    end
  end

  @doc """
  Changeset for updating branding configuration.
  """
  def branding_changeset(custom_domain, attrs) do
    custom_domain
    |> cast(attrs, [
      :brand_name,
      :logo_url,
      :primary_color,
      :custom_css,
      :colour,
      :instructions_pre_reveal,
      :instructions_reveal,
      :instructions_post_reveal,
      :description,
      :button_text_light,
      :allow_public_homepage,
      :allow_public_api,
      :font_family,
      :corner_style,
      :locale
    ])
    |> validate_length(:brand_name, max: 100)
    |> validate_length(:logo_url, max: 500)
    |> validate_format(:primary_color, ~r/^#[0-9a-fA-F]{6}$/,
      message: "must be a valid hex color"
    )
  end

  @doc """
  Changeset for updating mode settings.
  """
  def mode_changeset(custom_domain, attrs) do
    custom_domain
    |> cast(attrs, [:public_homepage, :anonymous_create, :incoming_secrets_email])
    |> validate_format(:incoming_secrets_email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email"
    )
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
