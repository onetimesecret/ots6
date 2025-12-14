defmodule OneTimeSecret.Secrets.SecretStore do
  @moduledoc """
  Redis-backed secret storage with TTL and timeline management.

  Secrets are stored as Redis hashes with automatic expiration.
  Timeline sorted sets enable efficient activity feed queries.

  ## Key Schema

  Secret hash: `ots:secret:{key}`
  ```
  {
    "encrypted_value": binary (serialized crypto bundle),
    "organization_id": uuid,
    "custom_domain_id": uuid | nil,
    "created_by_account_id": uuid | nil,
    "recipient_account_id": uuid | nil,
    "passphrase_required": "true" | "false",
    "created_at": iso8601 timestamp
  }
  ```

  Timeline sorted set: `ots:timeline:org:{org_id}`
  - Score: Unix timestamp
  - Member: Secret key
  """

  alias OneTimeSecret.Redis

  @key_prefix "ots:secret:"
  @timeline_prefix "ots:timeline:org:"
  @key_length 22
  @base62_chars "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
                |> String.graphemes()

  # Key Generation

  @doc """
  Generates a random 22-character base62 key for URL sharing.

  ## Examples

      iex> key = SecretStore.generate_key()
      iex> String.length(key)
      22
      iex> String.match?(key, ~r/^[0-9A-Za-z]+$/)
      true

  """
  @spec generate_key() :: String.t()
  def generate_key do
    1..@key_length
    |> Enum.map(fn _ -> Enum.random(@base62_chars) end)
    |> Enum.join()
  end

  # Secret CRUD

  @doc """
  Stores a secret in Redis with TTL.

  ## Parameters

    * `key` - 22-character secret key
    * `attrs` - Map with required keys:
      - `:encrypted_value` - Serialized crypto bundle (binary)
      - `:organization_id` - Organization UUID
      - `:ttl_seconds` - Time to live in seconds
      - `:created_at` - DateTime (defaults to now)

  Optional keys:
    * `:custom_domain_id` - Custom domain UUID
    * `:created_by_account_id` - Creator account UUID
    * `:recipient_account_id` - Recipient account UUID
    * `:passphrase_required` - Boolean (default: false)

  ## Examples

      iex> attrs = %{
      ...>   encrypted_value: <<1,2,3>>,
      ...>   organization_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   ttl_seconds: 3600
      ...> }
      iex> SecretStore.store("abc123xyz", attrs)
      {:ok, "abc123xyz"}

  """
  @spec store(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def store(key, attrs) when is_binary(key) and is_map(attrs) do
    redis_key = @key_prefix <> key
    ttl_seconds = Map.fetch!(attrs, :ttl_seconds)
    created_at = Map.get(attrs, :created_at, DateTime.utc_now())

    # Build hash fields
    fields =
      [
        "encrypted_value",
        Base.encode64(Map.fetch!(attrs, :encrypted_value)),
        "organization_id",
        Map.fetch!(attrs, :organization_id),
        "passphrase_required",
        to_string(Map.get(attrs, :passphrase_required, false)),
        "created_at",
        DateTime.to_iso8601(created_at)
      ]
      |> maybe_add_field("custom_domain_id", Map.get(attrs, :custom_domain_id))
      |> maybe_add_field("created_by_account_id", Map.get(attrs, :created_by_account_id))
      |> maybe_add_field("recipient_account_id", Map.get(attrs, :recipient_account_id))

    # Store hash and set TTL
    with {:ok, _} <- Redis.command(["HSET", redis_key | fields]),
         {:ok, _} <- Redis.command(["EXPIRE", redis_key, to_string(ttl_seconds)]) do
      {:ok, key}
    end
  end

  @doc """
  Fetches a secret from Redis.

  Returns `{:ok, map}` with string keys, or `{:error, :not_found}`.

  ## Examples

      iex> SecretStore.fetch("abc123xyz")
      {:ok, %{
        "encrypted_value" => <<1,2,3>>,
        "organization_id" => "550e8400-...",
        "passphrase_required" => false,
        "created_at" => ~U[2024-12-14 12:00:00Z]
      }}

      iex> SecretStore.fetch("nonexistent")
      {:error, :not_found}

  """
  @spec fetch(String.t()) :: {:ok, map()} | {:error, :not_found}
  def fetch(key) when is_binary(key) do
    redis_key = @key_prefix <> key

    case Redis.command(["HGETALL", redis_key]) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, fields} ->
        secret = parse_hash_fields(fields)
        {:ok, secret}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a secret from Redis.

  ## Examples

      iex> SecretStore.delete("abc123xyz")
      {:ok, 1}

      iex> SecretStore.delete("nonexistent")
      {:ok, 0}

  """
  @spec delete(String.t()) :: {:ok, integer()} | {:error, term()}
  def delete(key) when is_binary(key) do
    redis_key = @key_prefix <> key
    Redis.command(["DEL", redis_key])
  end

  @doc """
  Checks if a secret exists in Redis.

  ## Examples

      iex> SecretStore.exists?("abc123xyz")
      true

      iex> SecretStore.exists?("nonexistent")
      false

  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) when is_binary(key) do
    redis_key = @key_prefix <> key
    Redis.exists?(redis_key)
  end

  @doc """
  Returns remaining TTL in seconds, or nil if key doesn't exist.

  ## Examples

      iex> SecretStore.ttl("abc123xyz")
      {:ok, 3540}

      iex> SecretStore.ttl("nonexistent")
      {:ok, nil}

  """
  @spec ttl(String.t()) :: {:ok, integer() | nil} | {:error, term()}
  def ttl(key) when is_binary(key) do
    redis_key = @key_prefix <> key

    case Redis.command(["TTL", redis_key]) do
      {:ok, -2} -> {:ok, nil}
      {:ok, -1} -> {:ok, nil}
      {:ok, seconds} -> {:ok, seconds}
      {:error, reason} -> {:error, reason}
    end
  end

  # Timeline Management

  @doc """
  Adds a secret to an organization's timeline.

  ## Examples

      iex> SecretStore.add_to_timeline("550e8400-e29b-41d4-a716-446655440000", "abc123xyz")
      {:ok, 1}

  """
  @spec add_to_timeline(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def add_to_timeline(org_id, key) when is_binary(org_id) and is_binary(key) do
    timeline_key = @timeline_prefix <> org_id
    score = DateTime.utc_now() |> DateTime.to_unix() |> to_string()

    Redis.command(["ZADD", timeline_key, score, key])
  end

  @doc """
  Fetches recent secrets from an organization's timeline.

  Returns secrets in reverse chronological order (most recent first).

  ## Parameters

    * `org_id` - Organization UUID
    * `cursor` - Starting index (0 for first page)
    * `limit` - Maximum number of keys to return

  ## Examples

      iex> SecretStore.timeline("550e8400-e29b-41d4-a716-446655440000", 0, 20)
      {:ok, ["xyz789", "abc123"]}

  """
  @spec timeline(String.t(), integer(), integer()) :: {:ok, list(String.t())} | {:error, term()}
  def timeline(org_id, cursor \\ 0, limit \\ 20)
      when is_binary(org_id) and is_integer(cursor) and is_integer(limit) do
    timeline_key = @timeline_prefix <> org_id
    stop = cursor + limit - 1

    case Redis.command(["ZREVRANGE", timeline_key, to_string(cursor), to_string(stop)]) do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a secret from an organization's timeline.

  Used for cleanup after reveal or expiry.

  ## Examples

      iex> SecretStore.remove_from_timeline("550e8400-e29b-41d4-a716-446655440000", "abc123xyz")
      {:ok, 1}

  """
  @spec remove_from_timeline(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def remove_from_timeline(org_id, key) when is_binary(org_id) and is_binary(key) do
    timeline_key = @timeline_prefix <> org_id
    Redis.command(["ZREM", timeline_key, key])
  end

  # Private Helpers

  defp maybe_add_field(fields, _key, nil), do: fields

  defp maybe_add_field(fields, key, value) do
    fields ++ [key, value]
  end

  defp parse_hash_fields(fields) do
    fields
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn [key, value], acc ->
      parsed_value = parse_field_value(key, value)
      Map.put(acc, key, parsed_value)
    end)
  end

  defp parse_field_value("encrypted_value", value) do
    {:ok, decoded} = Base.decode64(value)
    decoded
  end

  defp parse_field_value("passphrase_required", "true"), do: true
  defp parse_field_value("passphrase_required", "false"), do: false

  defp parse_field_value("created_at", value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp parse_field_value(_key, value), do: value
end
