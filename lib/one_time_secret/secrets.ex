defmodule OneTimeSecret.Secrets do
  @moduledoc """
  The Secrets context.

  Orchestrates the complete secret lifecycle across:
  - Crypto: Encryption/decryption with optional passphrase layer
  - SecretStore (Redis): Ephemeral storage with TTL
  - Receipt (Postgres): Durable audit trail (2x TTL)

  ## Secret Lifecycle

  **Create:**
  1. Generate random key
  2. Encrypt value (server + optional passphrase)
  3. Store in Redis with TTL
  4. Create receipt in Postgres (expires after 2x TTL)
  5. Add to organization timeline

  **Reveal:**
  1. Fetch from Redis
  2. Decrypt (verify passphrase if required)
  3. Delete from Redis (one-time use)
  4. Update receipt (revealed_at, IP)
  5. Remove from timeline
  6. Return plaintext

  **Burn:**
  1. Verify ownership
  2. Delete from Redis
  3. Update receipt (burned_at)
  4. Remove from timeline
  """

  import Ecto.Query, warn: false
  alias OneTimeSecret.Repo
  alias OneTimeSecret.Secrets.{Receipt, SecretStore}
  alias OneTimeSecret.Crypto

  require Logger

  # Secret Creation

  @doc """
  Creates a new secret with encryption and durable receipt.

  ## Parameters

    * `attrs` - Map with required keys:
      - `:value` - The plaintext secret
      - `:ttl_seconds` - Time to live
      - `:organization_id` - Owning organization UUID

  ## Options

    * `:passphrase` - Optional passphrase for additional encryption layer
    * `:created_by_account_id` - Creator account UUID
    * `:custom_domain_id` - Domain context where created
    * `:recipient_account_id` - For member-to-member sharing

  ## Returns

  `{:ok, %{key: string, receipt: %Receipt{}}}` on success.
  `{:error, reason}` on failure.

  ## Examples

      iex> create_secret(%{value: "secret", ttl_seconds: 3600, organization_id: org_id})
      {:ok, %{key: "abc123...", receipt: %Receipt{}}}

      iex> create_secret(%{value: "secret", ttl_seconds: 3600, organization_id: org_id}, passphrase: "pass123")
      {:ok, %{key: "xyz789...", receipt: %Receipt{passphrase_required: true}}}

  """
  def create_secret(attrs, opts \\ []) do
    with {:ok, key} <- generate_unique_key(),
         {:ok, encrypted_bundle} <- encrypt_value(attrs, opts),
         {:ok, _} <- store_in_redis(key, attrs, encrypted_bundle, opts),
         {:ok, receipt} <- create_receipt(key, attrs, opts),
         {:ok, _} <- add_to_timeline(attrs.organization_id, key) do
      {:ok, %{key: key, receipt: receipt}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reveals a secret, decrypting and destroying it.

  ## Parameters

    * `key` - The 22-character secret key

  ## Options

    * `:passphrase` - Required if secret has passphrase protection
    * `:revealed_by_ip` - IP address of revealer (for audit)

  ## Returns

  `{:ok, plaintext}` on success.
  `{:error, :not_found}` if secret doesn't exist or expired.
  `{:error, :invalid_passphrase}` if passphrase is wrong.
  `{:error, :passphrase_required}` if passphrase needed but not provided.

  ## Examples

      iex> reveal_secret("abc123xyz")
      {:ok, "secret value"}

      iex> reveal_secret("abc123xyz", passphrase: "pass123")
      {:ok, "secret value"}

      iex> reveal_secret("nonexistent")
      {:error, :not_found}

  """
  def reveal_secret(key, opts \\ []) do
    with {:ok, redis_data} <- fetch_from_redis(key),
         {:ok, plaintext} <- decrypt_value(redis_data, opts),
         {:ok, _} <- delete_from_redis(key),
         {:ok, _receipt} <- update_receipt_revealed(key, opts),
         {:ok, _} <- remove_from_timeline(redis_data["organization_id"], key) do
      {:ok, plaintext}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Burns (deletes) a secret before it's revealed.

  Only the creator can burn their own secret.

  ## Examples

      iex> burn_secret("abc123xyz", account_id)
      {:ok, %Receipt{burned_at: ~U[...]}}

      iex> burn_secret("abc123xyz", wrong_account_id)
      {:error, :unauthorized}

  """
  def burn_secret(key, account_id) do
    with {:ok, redis_data} <- fetch_from_redis(key),
         :ok <- verify_ownership(redis_data, account_id),
         {:ok, _} <- delete_from_redis(key),
         {:ok, receipt} <- update_receipt_burned(key),
         {:ok, _} <- remove_from_timeline(redis_data["organization_id"], key) do
      {:ok, receipt}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets secret metadata without decrypting.

  ## Returns

  `{:ok, %{passphrase_required: bool, created_at: datetime, ttl: integer}}` on success.
  `{:error, :not_found}` if secret doesn't exist.

  ## Examples

      iex> get_secret_metadata("abc123xyz")
      {:ok, %{passphrase_required: true, created_at: ~U[...], ttl: 3540}}

  """
  def get_secret_metadata(key) do
    with {:ok, redis_data} <- fetch_from_redis(key),
         {:ok, ttl} <- SecretStore.ttl(key) do
      metadata = %{
        passphrase_required: redis_data["passphrase_required"],
        created_at: redis_data["created_at"],
        ttl: ttl
      }

      {:ok, metadata}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Receipt Helpers

  @doc """
  Gets a receipt by ID.

  ## Examples

      iex> get_receipt(receipt_id)
      %Receipt{}

      iex> get_receipt(nonexistent_id)
      ** (Ecto.NoResultsError)

  """
  def get_receipt(id), do: Repo.get!(Receipt, id)

  @doc """
  Gets a receipt by secret key.

  Returns `nil` if no receipt exists.

  ## Examples

      iex> get_receipt_by_key("abc123xyz")
      %Receipt{}

      iex> get_receipt_by_key("nonexistent")
      nil

  """
  def get_receipt_by_key(key) when is_binary(key) do
    Repo.get_by(Receipt, secret_key: key)
  end

  @doc """
  Lists receipts for an organization with pagination.

  Returns receipts in reverse chronological order.

  ## Examples

      iex> list_receipts_for_organization(org_id, page: 0, per_page: 20)
      [%Receipt{}, ...]

  """
  def list_receipts_for_organization(org_id, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = page * per_page

    Repo.all(
      from r in Receipt,
        where: r.organization_id == ^org_id,
        order_by: [desc: r.inserted_at],
        limit: ^per_page,
        offset: ^offset,
        preload: [:created_by, :recipient, :custom_domain]
    )
  end

  @doc """
  Lists receipts created by an account with pagination.

  ## Examples

      iex> list_receipts_for_account(account_id, page: 0, per_page: 20)
      [%Receipt{}, ...]

  """
  def list_receipts_for_account(account_id, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = page * per_page

    Repo.all(
      from r in Receipt,
        where: r.created_by_id == ^account_id,
        order_by: [desc: r.inserted_at],
        limit: ^per_page,
        offset: ^offset,
        preload: [:organization, :custom_domain, :recipient]
    )
  end

  # Private Helpers

  defp generate_unique_key do
    key = SecretStore.generate_key()

    if SecretStore.exists?(key) do
      # Collision (astronomically unlikely) - try again
      generate_unique_key()
    else
      {:ok, key}
    end
  end

  defp encrypt_value(%{value: value}, opts) do
    passphrase = Keyword.get(opts, :passphrase)

    encrypt_opts =
      if passphrase do
        [passphrase: passphrase]
      else
        []
      end

    case Crypto.encrypt(value, encrypt_opts) do
      {:ok, bundle} ->
        serialized = Crypto.serialize(bundle)
        {:ok, serialized}

      {:error, reason} ->
        {:error, {:encryption_failed, reason}}
    end
  end

  defp store_in_redis(key, attrs, encrypted_bundle, opts) do
    store_attrs = %{
      encrypted_value: encrypted_bundle,
      organization_id: attrs.organization_id,
      ttl_seconds: attrs.ttl_seconds,
      passphrase_required: Keyword.has_key?(opts, :passphrase),
      created_at: DateTime.utc_now()
    }

    store_attrs =
      store_attrs
      |> maybe_put(:custom_domain_id, Keyword.get(opts, :custom_domain_id))
      |> maybe_put(:created_by_account_id, Keyword.get(opts, :created_by_account_id))
      |> maybe_put(:recipient_account_id, Keyword.get(opts, :recipient_account_id))

    SecretStore.store(key, store_attrs)
  end

  defp create_receipt(key, attrs, opts) do
    created_at = DateTime.utc_now()
    receipt_expires_at = Receipt.calculate_receipt_expires_at(created_at, attrs.ttl_seconds)

    receipt_attrs = %{
      secret_key: key,
      ttl_seconds: attrs.ttl_seconds,
      passphrase_required: Keyword.has_key?(opts, :passphrase),
      receipt_expires_at: receipt_expires_at,
      organization_id: attrs.organization_id
    }

    receipt_attrs =
      receipt_attrs
      |> maybe_put(:custom_domain_id, Keyword.get(opts, :custom_domain_id))
      |> maybe_put(:created_by_id, Keyword.get(opts, :created_by_account_id))
      |> maybe_put(:recipient_id, Keyword.get(opts, :recipient_account_id))

    %Receipt{}
    |> Receipt.changeset(receipt_attrs)
    |> Repo.insert()
  end

  defp add_to_timeline(org_id, key) do
    SecretStore.add_to_timeline(org_id, key)
  end

  defp fetch_from_redis(key) do
    case SecretStore.fetch(key) do
      {:ok, data} -> {:ok, data}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decrypt_value(redis_data, opts) do
    encrypted_bundle = Crypto.deserialize(redis_data["encrypted_value"])
    passphrase = Keyword.get(opts, :passphrase)

    decrypt_opts =
      if passphrase do
        [passphrase: passphrase]
      else
        []
      end

    case Crypto.decrypt(encrypted_bundle, decrypt_opts) do
      {:ok, plaintext} ->
        {:ok, plaintext}

      {:error, :passphrase_required} ->
        {:error, :passphrase_required}

      {:error, :passphrase_verification_failed} ->
        {:error, :invalid_passphrase}

      {:error, reason} ->
        {:error, {:decryption_failed, reason}}
    end
  end

  defp delete_from_redis(key) do
    case SecretStore.delete(key) do
      {:ok, _} ->
        {:ok, :deleted}

      {:error, reason} ->
        # Log but don't fail - secret might already be expired
        Logger.warning("Failed to delete secret from Redis: #{inspect(reason)}")
        {:ok, :delete_failed}
    end
  end

  defp update_receipt_revealed(key, opts) do
    receipt = get_receipt_by_key(key)
    revealed_by_ip = Keyword.get(opts, :revealed_by_ip)

    if receipt do
      receipt
      |> Receipt.reveal_changeset(revealed_by_ip)
      |> Repo.update()
    else
      # Receipt might not exist (edge case) - log and continue
      Logger.warning("Receipt not found for key: #{key}")
      {:ok, nil}
    end
  end

  defp update_receipt_burned(key) do
    receipt = get_receipt_by_key(key)

    if receipt do
      receipt
      |> Receipt.burn_changeset()
      |> Repo.update()
    else
      Logger.warning("Receipt not found for key: #{key}")
      {:ok, nil}
    end
  end

  defp remove_from_timeline(org_id, key) do
    SecretStore.remove_from_timeline(org_id, key)
  end

  defp verify_ownership(redis_data, account_id) do
    created_by = Map.get(redis_data, "created_by_account_id")

    if created_by == account_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
