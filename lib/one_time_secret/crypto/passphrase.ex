defmodule OneTimeSecret.Crypto.Passphrase do
  @moduledoc """
  Passphrase-based encryption using Argon2id key derivation.

  Provides an additional encryption layer on top of server-side encryption.
  Users can optionally protect secrets with a passphrase that only they know.

  ## Key Derivation

  Uses Argon2id (from `argon2_elixir`) to derive a 32-byte encryption key from:
  - User's passphrase
  - Random 16-byte salt (unique per secret)

  ## Encryption

  The derived key is used with AES-256-GCM (via `OneTimeSecret.Crypto.AesGcm`)
  to encrypt the plaintext.

  ## Storage

  Returns a bundle containing:
  - `salt` - 16-byte random salt (needed for key re-derivation)
  - `nonce` - 12-byte nonce (from AES-GCM)
  - `ciphertext` - Encrypted data
  - `tag` - 16-byte authentication tag (from AES-GCM)

  """

  alias OneTimeSecret.Crypto.AesGcm

  @salt_size 16

  @doc """
  Derives a 32-byte encryption key from a passphrase and salt.

  Uses Argon2id with these parameters:
  - Memory cost: 65536 KB (~64 MB)
  - Time cost: 3 iterations
  - Parallelism: 4 threads
  - Output length: 32 bytes

  ## Examples

      iex> salt = :crypto.strong_rand_bytes(16)
      iex> key = Passphrase.derive_key("my passphrase", salt)
      iex> byte_size(key)
      32

  """
  @spec derive_key(String.t(), binary()) :: binary()
  def derive_key(passphrase, salt) when is_binary(passphrase) and byte_size(salt) == 16 do
    Argon2.Base.hash_password(passphrase, salt,
      t_cost: 3,
      m_cost: 16,
      parallelism: 4,
      hashlen: 32,
      format: :raw_hash
    )
  end

  @doc """
  Encrypts plaintext with a passphrase-derived key.

  ## Process

  1. Generate random 16-byte salt
  2. Derive 32-byte key from passphrase + salt using Argon2id
  3. Encrypt plaintext with AES-256-GCM

  ## Returns

  `{:ok, bundle}` where bundle contains:
  - `salt` - Random salt (needed for decryption)
  - `nonce` - AES-GCM nonce
  - `ciphertext` - Encrypted data
  - `tag` - Authentication tag

  ## Examples

      iex> {:ok, bundle} = Passphrase.wrap("secret data", "my passphrase")
      iex> Map.keys(bundle)
      [:salt, :nonce, :ciphertext, :tag]

  """
  @spec wrap(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def wrap(plaintext, passphrase) when is_binary(plaintext) and is_binary(passphrase) do
    salt = :crypto.strong_rand_bytes(@salt_size)
    key = derive_key(passphrase, salt)

    case AesGcm.encrypt(plaintext, key, "") do
      {:ok, aes_bundle} ->
        bundle = %{
          salt: salt,
          nonce: aes_bundle.nonce,
          ciphertext: aes_bundle.ciphertext,
          tag: aes_bundle.tag
        }

        {:ok, bundle}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Decrypts ciphertext with a passphrase.

  ## Parameters

    * `ciphertext` - Encrypted data
    * `passphrase` - User's passphrase
    * `salt` - Salt used during encryption (from bundle)
    * `nonce` - Nonce used during encryption (from bundle)
    * `tag` - Authentication tag (from bundle)

  ## Returns

  `{:ok, plaintext}` on success.
  `{:error, :passphrase_verification_failed}` if passphrase is incorrect.

  ## Examples

      iex> {:ok, bundle} = Passphrase.wrap("secret", "pass123")
      iex> {:ok, plaintext} = Passphrase.unwrap(
      ...>   bundle.ciphertext,
      ...>   "pass123",
      ...>   bundle.salt,
      ...>   bundle.nonce,
      ...>   bundle.tag
      ...> )
      iex> plaintext
      "secret"

  """
  @spec unwrap(binary(), String.t(), binary(), binary(), binary()) ::
          {:ok, String.t()} | {:error, term()}
  def unwrap(ciphertext, passphrase, salt, nonce, tag)
      when is_binary(ciphertext) and is_binary(passphrase) and byte_size(salt) == 16 do
    key = derive_key(passphrase, salt)

    aes_bundle = %{
      v: 1,
      alg: "aes-256-gcm",
      nonce: nonce,
      ciphertext: ciphertext,
      tag: tag
    }

    case AesGcm.decrypt(aes_bundle, key, "") do
      {:ok, plaintext} ->
        {:ok, plaintext}

      {:error, :decryption_failed} ->
        {:error, :passphrase_verification_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
