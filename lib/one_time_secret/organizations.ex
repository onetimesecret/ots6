defmodule OneTimeSecret.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Organizations.{Organization, Membership}
  alias OneTimeSecret.Accounts.Account
  alias OneTimeSecret.Plans

  # Organization CRUD

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the Organization does not exist.

  ## Examples

      iex> get_organization!(123)
      %Organization{}

      iex> get_organization!(456)
      ** (Ecto.NoResultsError)

  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Gets an organization by slug.

  Returns `nil` if no organization exists with that slug.

  ## Examples

      iex> get_organization_by_slug("acme-corp")
      %Organization{}

      iex> get_organization_by_slug("nonexistent")
      nil

  """
  def get_organization_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @doc """
  Lists all organizations an account belongs to (via memberships).

  ## Examples

      iex> list_organizations_for_account(account_id)
      [%Organization{}, ...]

  """
  def list_organizations_for_account(account_id) do
    Repo.all(
      from o in Organization,
        join: m in Membership,
        on: m.organization_id == o.id,
        where: m.account_id == ^account_id,
        order_by: [asc: o.name]
    )
  end

  @doc """
  Creates an organization.

  ## Examples

      iex> create_organization(%{name: "Acme Corp", slug: "acme", plan_id: plan.id, owner_id: account.id})
      {:ok, %Organization{}}

      iex> create_organization(%{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization.

  ## Examples

      iex> update_organization(organization, %{name: "New Name"})
      {:ok, %Organization{}}

      iex> update_organization(organization, %{slug: "invalid slug!"})
      {:error, %Ecto.Changeset{}}

  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.profile_changeset(attrs)
    |> Repo.update()
  end

  # Membership CRUD

  @doc """
  Gets a single membership.

  Raises `Ecto.NoResultsError` if the Membership does not exist.

  ## Examples

      iex> get_membership!(123)
      %Membership{}

      iex> get_membership!(456)
      ** (Ecto.NoResultsError)

  """
  def get_membership!(id), do: Repo.get!(Membership, id)

  @doc """
  Gets a membership by account_id and organization_id.

  Returns `nil` if no membership exists.

  ## Examples

      iex> get_membership(account_id, organization_id)
      %Membership{}

      iex> get_membership(account_id, nonexistent_org_id)
      nil

  """
  def get_membership(account_id, organization_id) do
    Repo.get_by(Membership, account_id: account_id, organization_id: organization_id)
  end

  @doc """
  Lists all memberships for an organization.

  ## Examples

      iex> list_memberships_for_organization(organization_id)
      [%Membership{}, ...]

  """
  def list_memberships_for_organization(organization_id) do
    Repo.all(
      from m in Membership,
        where: m.organization_id == ^organization_id,
        order_by: [asc: m.joined_at],
        preload: [:account]
    )
  end

  @doc """
  Creates a membership.

  ## Examples

      iex> create_membership(%{account_id: account.id, organization_id: org.id, role: :member})
      {:ok, %Membership{}}

      iex> create_membership(%{})
      {:error, %Ecto.Changeset{}}

  """
  def create_membership(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a membership's role.

  ## Examples

      iex> update_membership_role(membership, %{role: :admin})
      {:ok, %Membership{}}

      iex> update_membership_role(membership, %{role: :invalid})
      {:error, %Ecto.Changeset{}}

  """
  def update_membership_role(%Membership{} = membership, attrs) do
    membership
    |> Membership.role_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a membership.

  ## Examples

      iex> delete_membership(membership)
      {:ok, %Membership{}}

      iex> delete_membership(membership)
      {:error, %Ecto.Changeset{}}

  """
  def delete_membership(%Membership{} = membership) do
    Repo.delete(membership)
  end

  # Personal Organization Auto-Creation

  @doc """
  Registers an account with an automatic personal organization.

  This is the primary registration flow. It atomically creates:
  1. Account (with password hashing)
  2. Personal organization (free plan, "{email}'s Workspace")
  3. Owner membership (connects account to org)

  Uses Ecto.Multi for atomicity—either all succeed or all fail.

  ## Examples

      iex> register_account_with_personal_org(%{email: "[email protected]", password: "secret123456"})
      {:ok, %{account: %Account{}, organization: %Organization{}, membership: %Membership{}}}

      iex> register_account_with_personal_org(%{email: "invalid"})
      {:error, :account, %Ecto.Changeset{}, %{}}

  """
  def register_account_with_personal_org(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:account, fn _repo, _changes ->
      %Account{}
      |> Account.registration_changeset(attrs)
      |> Repo.insert()
    end)
    |> Ecto.Multi.run(:organization, fn _repo, %{account: account} ->
      free_plan = Plans.get_plan_by_slug("free")

      unless free_plan do
        raise "Free plan not found! Run: mix run priv/repo/seeds.exs"
      end

      org_attrs = %{
        name: "#{account.email}'s Workspace",
        slug: generate_slug(account.email),
        personal: true,
        plan_id: free_plan.id,
        owner_id: account.id
      }

      %Organization{}
      |> Organization.changeset(org_attrs)
      |> Repo.insert()
    end)
    |> Ecto.Multi.run(:membership, fn _repo, %{account: account, organization: org} ->
      membership_attrs = %{
        account_id: account.id,
        organization_id: org.id,
        role: :owner,
        provisioned_via: :invite
      }

      %Membership{}
      |> Membership.changeset(membership_attrs)
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, failed_operation, changeset, _changes} -> {:error, failed_operation, changeset}
    end
  end

  # Private helpers

  defp generate_slug(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> Kernel.<>("-#{:rand.uniform(9999)}")
  end
end
