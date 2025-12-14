defmodule OneTimeSecret.CustomDomains do
  @moduledoc """
  The CustomDomains context.
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.CustomDomains.CustomDomain

  # CRUD Operations

  @doc """
  Gets a single custom domain.

  Raises `Ecto.NoResultsError` if the CustomDomain does not exist.

  ## Examples

      iex> get_custom_domain!(123)
      %CustomDomain{}

      iex> get_custom_domain!(456)
      ** (Ecto.NoResultsError)

  """
  def get_custom_domain!(id), do: Repo.get!(CustomDomain, id)

  @doc """
  Gets a custom domain by hostname.

  Returns `nil` if no custom domain exists with that hostname.

  ## Examples

      iex> get_custom_domain_by_hostname("secrets.clientco.com")
      %CustomDomain{}

      iex> get_custom_domain_by_hostname("nonexistent.com")
      nil

  """
  def get_custom_domain_by_hostname(hostname) when is_binary(hostname) do
    Repo.get_by(CustomDomain, hostname: String.downcase(hostname))
  end

  @doc """
  Gets a verified custom domain by hostname.

  Returns `nil` if no verified custom domain exists with that hostname.
  Used by routing to only match verified domains.

  ## Examples

      iex> get_verified_custom_domain_by_hostname("secrets.clientco.com")
      %CustomDomain{verified_at: ~U[2024-01-15 10:00:00Z]}

      iex> get_verified_custom_domain_by_hostname("unverified.com")
      nil

  """
  def get_verified_custom_domain_by_hostname(hostname) when is_binary(hostname) do
    Repo.one(
      from cd in CustomDomain,
        where: cd.hostname == ^String.downcase(hostname),
        where: not is_nil(cd.verified_at)
    )
  end

  @doc """
  Lists all custom domains for an organization.

  ## Examples

      iex> list_custom_domains_for_organization(organization_id)
      [%CustomDomain{}, ...]

  """
  def list_custom_domains_for_organization(organization_id) do
    Repo.all(
      from cd in CustomDomain,
        where: cd.organization_id == ^organization_id,
        order_by: [asc: cd.hostname]
    )
  end

  @doc """
  Creates a custom domain.

  Automatically generates a verification token.

  ## Examples

      iex> create_custom_domain(org_id, %{hostname: "secrets.example.com"})
      {:ok, %CustomDomain{}}

      iex> create_custom_domain(org_id, %{hostname: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_custom_domain(organization_id, attrs) do
    attrs_with_org = Map.put(attrs, :organization_id, organization_id)

    %CustomDomain{}
    |> CustomDomain.changeset(attrs_with_org)
    |> Repo.insert()
  end

  @doc """
  Updates a custom domain.

  ## Examples

      iex> update_custom_domain(custom_domain, %{hostname: "new.example.com"})
      {:ok, %CustomDomain{}}

      iex> update_custom_domain(custom_domain, %{hostname: "invalid!"})
      {:error, %Ecto.Changeset{}}

  """
  def update_custom_domain(%CustomDomain{} = custom_domain, attrs) do
    custom_domain
    |> CustomDomain.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates custom domain branding configuration.

  ## Examples

      iex> update_custom_domain_branding(custom_domain, %{brand_name: "ClientCo", logo_url: "https://..."})
      {:ok, %CustomDomain{}}

  """
  def update_custom_domain_branding(%CustomDomain{} = custom_domain, attrs) do
    custom_domain
    |> CustomDomain.branding_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates custom domain mode settings.

  ## Examples

      iex> update_custom_domain_modes(custom_domain, %{public_homepage: true})
      {:ok, %CustomDomain{}}

  """
  def update_custom_domain_modes(%CustomDomain{} = custom_domain, attrs) do
    custom_domain
    |> CustomDomain.mode_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a custom domain.

  ## Examples

      iex> delete_custom_domain(custom_domain)
      {:ok, %CustomDomain{}}

      iex> delete_custom_domain(custom_domain)
      {:error, %Ecto.Changeset{}}

  """
  def delete_custom_domain(%CustomDomain{} = custom_domain) do
    Repo.delete(custom_domain)
  end

  # Verification

  @doc """
  Generates a secure random verification token.

  Returns a URL-safe base64 string (32 bytes of randomness).

  ## Examples

      iex> generate_verification_token()
      "Xy7pQ9mN..."

  """
  def generate_verification_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Verifies a custom domain by checking DNS TXT record.

  Queries for a TXT record at `_onetimesecret.{hostname}` and compares
  the value to the stored verification token.

  If verification succeeds, sets `verified_at` to the current timestamp.

  ## Options

    * `:skip_dns_check` - When true, skips DNS verification (for testing). Default: false.

  ## Examples

      iex> verify_domain(custom_domain)
      {:ok, %CustomDomain{verified_at: ~U[2024-01-15 10:00:00Z]}}

      iex> verify_domain(custom_domain, skip_dns_check: true)
      {:ok, %CustomDomain{verified_at: ~U[2024-01-15 10:00:00Z]}}

      iex> verify_domain(custom_domain)
      {:error, :dns_verification_failed}

  """
  def verify_domain(%CustomDomain{} = custom_domain, opts \\ []) do
    skip_dns = Keyword.get(opts, :skip_dns_check, false)

    if skip_dns do
      # Skip DNS check, mark as verified
      custom_domain
      |> CustomDomain.verification_changeset(true)
      |> Repo.update()
    else
      case check_dns_txt_record(custom_domain.hostname, custom_domain.verification_token) do
        :ok ->
          custom_domain
          |> CustomDomain.verification_changeset(true)
          |> Repo.update()

        {:error, _reason} ->
          {:error, :dns_verification_failed}
      end
    end
  end

  # Private Helpers

  defp check_dns_txt_record(hostname, expected_token) do
    verification_hostname = "_onetimesecret.#{hostname}"

    case :inet_res.lookup(
           String.to_charlist(verification_hostname),
           :in,
           :txt,
           timeout: 5000
         ) do
      [] ->
        {:error, :no_txt_record}

      records ->
        # TXT records come back as lists of charlists
        # e.g., [['verification-token-here']]
        found_token =
          records
          |> List.flatten()
          |> Enum.map(&List.to_string/1)
          |> Enum.any?(fn value -> value == expected_token end)

        if found_token do
          :ok
        else
          {:error, :token_mismatch}
        end
    end
  rescue
    _ ->
      {:error, :dns_query_failed}
  end
end
