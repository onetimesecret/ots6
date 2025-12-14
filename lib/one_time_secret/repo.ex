defmodule OneTimeSecret.Repo do
  use Ecto.Repo,
    otp_app: :one_time_secret,
    adapter: Ecto.Adapters.SQLite3
end
