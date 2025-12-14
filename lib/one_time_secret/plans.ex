defmodule OneTimeSecret.Plans do
  @moduledoc """
  The Plans context.
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Plans.Plan

  @doc """
  Returns the list of plans ordered by name.

  ## Examples

      iex> list_plans()
      [%Plan{}, ...]

  """
  def list_plans do
    Repo.all(from p in Plan, order_by: p.name)
  end

  @doc """
  Gets a single plan.

  Raises `Ecto.NoResultsError` if the Plan does not exist.

  ## Examples

      iex> get_plan!(123)
      %Plan{}

      iex> get_plan!(456)
      ** (Ecto.NoResultsError)

  """
  def get_plan!(id), do: Repo.get!(Plan, id)

  @doc """
  Gets a plan by slug (free, pro, business, enterprise).

  Returns `nil` if the plan does not exist.

  ## Examples

      iex> get_plan_by_slug("free")
      %Plan{}

      iex> get_plan_by_slug("unknown")
      nil

  """
  def get_plan_by_slug(slug) do
    Repo.get_by(Plan, slug: slug)
  end
end
