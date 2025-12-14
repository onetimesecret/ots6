defmodule OneTimeSecret.Redis do
  @moduledoc """
  Redis connection pool and low-level command wrapper.

  Provides a simple interface to execute Redis commands through a named Redix connection.
  The connection is started in the application supervision tree.

  ## Usage

      # Execute a command
      {:ok, "OK"} = Redis.command(["SET", "key", "value"])

      # Execute a pipeline
      {:ok, results} = Redis.pipeline([["SET", "key1", "val1"], ["SET", "key2", "val2"]])

  """

  @doc """
  Executes a single Redis command.

  ## Examples

      iex> Redis.command(["SET", "mykey", "myvalue"])
      {:ok, "OK"}

      iex> Redis.command(["GET", "mykey"])
      {:ok, "myvalue"}

      iex> Redis.command(["GET", "nonexistent"])
      {:ok, nil}

  """
  @spec command(list()) :: {:ok, term()} | {:error, term()}
  def command(command) do
    Redix.command(:redix, command)
  end

  @doc """
  Executes a Redis pipeline (multiple commands atomically).

  ## Examples

      iex> Redis.pipeline([["SET", "k1", "v1"], ["SET", "k2", "v2"]])
      {:ok, ["OK", "OK"]}

  """
  @spec pipeline(list(list())) :: {:ok, list(term())} | {:error, term()}
  def pipeline(commands) do
    Redix.pipeline(:redix, commands)
  end

  @doc """
  Executes a command, raising on error.

  ## Examples

      iex> Redis.command!(["SET", "key", "value"])
      "OK"

  """
  @spec command!(list()) :: term()
  def command!(command) do
    case command(command) do
      {:ok, result} -> result
      {:error, reason} -> raise "Redis command failed: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if a key exists in Redis.

  ## Examples

      iex> Redis.exists?("mykey")
      true

      iex> Redis.exists?("nonexistent")
      false

  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    case command(["EXISTS", key]) do
      {:ok, 1} -> true
      {:ok, 0} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Deletes one or more keys from Redis.

  Returns the number of keys deleted.

  ## Examples

      iex> Redis.del("key1")
      {:ok, 1}

      iex> Redis.del(["key1", "key2", "key3"])
      {:ok, 3}

  """
  @spec del(String.t() | list(String.t())) :: {:ok, integer()} | {:error, term()}
  def del(key) when is_binary(key) do
    command(["DEL", key])
  end

  def del(keys) when is_list(keys) do
    command(["DEL" | keys])
  end
end
