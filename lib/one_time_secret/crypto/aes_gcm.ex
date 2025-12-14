defmodule OneTimeSecret.Crypto.AesGcm do
  @moduledoc """
  AES-256-GCM encryption provider.

  Implements authenticated encryption with associated data (AEAD) using AES-256-GCM.

  ## Algorithm Details

  - **Cipher**: AES-256-GCM (Galois/Counter Mode)
  - **Key size**: 32 bytes (256 bits)
  - **Nonce size**: 12 bytes (96 bits) - randomly generated per encryption
  - **Tag size**: 16 bytes (128 bits) - authentication tag

  ## Returns

  Encryption returns a structured map:

      %{
        v: 1,                    # Version for future algorithm changes
        alg: "aes-256-gcm",      # Algorithm identifier
        nonce: <<...>>,          # 12-byte nonce (base64 for JSON)
        ciphertext: <<...>>,     # Encrypted data
        tag: <<...>>             # 16-byte authentication tag
      }

  """

  @nonce_size 12
  @tag_size 16

  @doc """
  Encrypts plaintext using AES-256-GCM.

  ## Parameters

    * `plaintext` - Binary data to encrypt
    * `key` - 32-byte encryption key
    * `aad` - Additional authenticated data (optional, default: "")

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> {:ok, bundle} = AesGcm.encrypt("secret", key, "")
      iex> bundle.alg
      "aes-256-gcm"

  """
  @spec encrypt(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def encrypt(plaintext, key, aad \\ "")
      when is_binary(plaintext) and is_binary(key) and byte_size(key) == 32 do
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, aad, @tag_size, true) do
      {ciphertext, tag} ->
        bundle = %{
          v: 1,
          alg: "aes-256-gcm",
          nonce: nonce,
          ciphertext: ciphertext,
          tag: tag
        }

        {:ok, bundle}

      error ->
        {:error, {:encryption_failed, error}}
    end
  end

  def encrypt(_plaintext, key, _aad) when byte_size(key) != 32 do
    {:error, :invalid_key_size}
  end

  @doc """
  Decrypts an AES-256-GCM bundle.

  ## Parameters

    * `bundle` - Map containing nonce, ciphertext, and tag
    * `key` - 32-byte decryption key (must match encryption key)
    * `aad` - Additional authenticated data (must match encryption AAD)

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> {:ok, bundle} = AesGcm.encrypt("secret", key, "")
      iex> {:ok, plaintext} = AesGcm.decrypt(bundle, key, "")
      iex> plaintext
      "secret"

  """
  @spec decrypt(map(), binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def decrypt(bundle, key, aad \\ "")
      when is_map(bundle) and is_binary(key) and byte_size(key) == 32 do
    with {:ok, nonce} <- extract_field(bundle, :nonce),
         {:ok, ciphertext} <- extract_field(bundle, :ciphertext),
         {:ok, tag} <- extract_field(bundle, :tag) do
      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             aad,
             tag,
             false
           ) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        :error ->
          {:error, :decryption_failed}
      end
    end
  end

  def decrypt(_bundle, key, _aad) when byte_size(key) != 32 do
    {:error, :invalid_key_size}
  end

  # Private Helpers

  defp extract_field(bundle, field) do
    case Map.fetch(bundle, field) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_field, field}}
    end
  end
end
