defmodule OneTimeSecret.Crypto do
  @moduledoc """
  High-level encryption API for OneTimeSecret.

  Provides a behavior definition and dispatcher for encryption operations.
  Uses AES-256-GCM for server-side encryption with a master key from config.

  ## Configuration

  The master encryption key must be set in your config:

      config :one_time_secret, :encryption_key, "base64_encoded_32_byte_key"

  Generate a key:

      :crypto.strong_rand_bytes(32) |> Base.encode64()

  ## Usage

      # Server-side encryption only
      {:ok, encrypted} = Crypto.encrypt("my secret")

      # With passphrase protection
      {:ok, encrypted} = Crypto.encrypt("my secret", passphrase: "user_passphrase")

      # Decrypt
      {:ok, plaintext} = Crypto.decrypt(encrypted)

      # Decrypt with passphrase
      {:ok, plaintext} = Crypto.decrypt(encrypted, passphrase: "user_passphrase")

  """

  alias OneTimeSecret.Crypto.AesGcm
  alias OneTimeSecret.Crypto.Passphrase

  @type plaintext :: binary()
  @type ciphertext_bundle :: map()
  @type encrypt_opts :: [passphrase: binary(), aad: binary()]
  @type decrypt_opts :: [passphrase: binary(), aad: binary()]

  @doc """
  Encrypts plaintext with server-side encryption and optional passphrase layer.

  ## Options

    * `:passphrase` - If provided, adds a passphrase encryption layer before server encryption
    * `:aad` - Additional authenticated data (AAD) for AEAD encryption

  ## Examples

      iex> {:ok, encrypted} = Crypto.encrypt("my secret")
      {:ok, %{v: 1, server: %{...}}}

      iex> {:ok, encrypted} = Crypto.encrypt("my secret", passphrase: "pass123")
      {:ok, %{v: 1, server: %{...}, passphrase: %{...}}}

  """
  @spec encrypt(plaintext(), encrypt_opts()) :: {:ok, ciphertext_bundle()} | {:error, term()}
  def encrypt(plaintext, opts \\ []) when is_binary(plaintext) do
    master_key = get_master_key()
    passphrase = Keyword.get(opts, :passphrase)
    aad = Keyword.get(opts, :aad, "")

    with {:ok, payload} <- maybe_passphrase_encrypt(plaintext, passphrase),
         {:ok, server_encrypted} <- AesGcm.encrypt(payload, master_key, aad) do
      bundle = %{
        v: 1,
        server: server_encrypted
      }

      bundle =
        if passphrase do
          Map.put(bundle, :passphrase_protected, true)
        else
          bundle
        end

      {:ok, bundle}
    end
  end

  @doc """
  Decrypts a ciphertext bundle.

  First decrypts the server layer with the master key, then optionally
  decrypts the passphrase layer if `:passphrase` is provided.

  ## Options

    * `:passphrase` - Required if the bundle has a passphrase layer
    * `:aad` - Must match the AAD used during encryption

  ## Examples

      iex> {:ok, plaintext} = Crypto.decrypt(encrypted)
      {:ok, "my secret"}

      iex> {:ok, plaintext} = Crypto.decrypt(encrypted, passphrase: "pass123")
      {:ok, "my secret"}

      iex> Crypto.decrypt(encrypted, passphrase: "wrong")
      {:error, :passphrase_verification_failed}

  """
  @spec decrypt(ciphertext_bundle(), decrypt_opts()) :: {:ok, plaintext()} | {:error, term()}
  def decrypt(bundle, opts \\ []) when is_map(bundle) do
    master_key = get_master_key()
    passphrase = Keyword.get(opts, :passphrase)
    aad = Keyword.get(opts, :aad, "")

    with {:ok, server_decrypted} <- AesGcm.decrypt(bundle.server, master_key, aad),
         {:ok, plaintext} <- maybe_passphrase_decrypt(server_decrypted, bundle, passphrase) do
      {:ok, plaintext}
    end
  end

  @doc """
  Serializes a ciphertext bundle to a binary format for storage.

  Uses `:erlang.term_to_binary/1` for compact serialization.

  ## Examples

      iex> {:ok, encrypted} = Crypto.encrypt("secret")
      iex> binary = Crypto.serialize(encrypted)
      iex> is_binary(binary)
      true

  """
  @spec serialize(ciphertext_bundle()) :: binary()
  def serialize(bundle) when is_map(bundle) do
    :erlang.term_to_binary(bundle)
  end

  @doc """
  Deserializes a binary bundle back to a map.

  ## Examples

      iex> {:ok, encrypted} = Crypto.encrypt("secret")
      iex> binary = Crypto.serialize(encrypted)
      iex> deserialized = Crypto.deserialize(binary)
      iex> deserialized == encrypted
      true

  """
  @spec deserialize(binary()) :: ciphertext_bundle()
  def deserialize(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  end

  # Private Helpers

  defp get_master_key do
    case Application.get_env(:one_time_secret, :encryption_key) do
      nil ->
        raise """
        No encryption key configured!

        Add to config/runtime.exs:

          config :one_time_secret, :encryption_key, System.get_env("ENCRYPTION_KEY")

        Generate a key:

          mix run -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'

        """

      encoded_key ->
        case Base.decode64(encoded_key) do
          {:ok, key} when byte_size(key) == 32 ->
            key

          {:ok, key} ->
            raise "Encryption key must be exactly 32 bytes, got #{byte_size(key)} bytes"

          :error ->
            raise "Encryption key must be base64-encoded"
        end
    end
  end

  defp maybe_passphrase_encrypt(plaintext, nil), do: {:ok, plaintext}

  defp maybe_passphrase_encrypt(plaintext, passphrase) do
    Passphrase.wrap(plaintext, passphrase)
    |> case do
      {:ok, %{ciphertext: ciphertext, salt: salt, nonce: nonce, tag: tag}} ->
        {:ok, %{passphrase: %{salt: salt, nonce: nonce, tag: tag}, payload: ciphertext}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_passphrase_decrypt(server_decrypted, bundle, nil) do
    if Map.get(bundle, :passphrase_protected) do
      {:error, :passphrase_required}
    else
      {:ok, server_decrypted}
    end
  end

  defp maybe_passphrase_decrypt(server_decrypted, bundle, passphrase) do
    case Map.get(bundle, :passphrase_protected) do
      true ->
        passphrase_bundle = Map.get(bundle, :passphrase)

        unless passphrase_bundle do
          {:error, :missing_passphrase_metadata}
        else
          Passphrase.unwrap(
            server_decrypted.payload,
            passphrase,
            passphrase_bundle.salt,
            passphrase_bundle.nonce,
            passphrase_bundle.tag
          )
        end

      false ->
        {:error, :passphrase_not_required}

      # For bundles without passphrase_protected key
      nil ->
        {:ok, server_decrypted}
    end
  end
end
