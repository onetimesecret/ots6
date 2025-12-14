# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     OneTimeSecret.Repo.insert!(%OneTimeSecret.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias OneTimeSecret.Repo
alias OneTimeSecret.Plans.Plan

# Free Plan
%Plan{}
|> Plan.changeset(%{
  name: "Free",
  slug: "free",
  max_secret_size_bytes: 10_240,
  max_ttl_seconds: 604_800,
  max_secrets_per_day: 500,
  max_custom_domains: 0,
  max_members: nil,
  custom_branding: false,
  member_auth_on_custom_domain: false,
  admin_on_custom_domain: false,
  member_to_member_sharing: false,
  incoming_secrets: false,
  api_access: true,
  sso_enabled: false,
  audit_log: false
})
|> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)

# Pro Plan
%Plan{}
|> Plan.changeset(%{
  name: "Pro",
  slug: "pro",
  max_secret_size_bytes: 102_400,
  max_ttl_seconds: 2_592_000,
  max_secrets_per_day: 5_000,
  max_custom_domains: 1,
  max_members: nil,
  custom_branding: true,
  member_auth_on_custom_domain: false,
  admin_on_custom_domain: false,
  member_to_member_sharing: false,
  incoming_secrets: false,
  api_access: true,
  sso_enabled: false,
  audit_log: true
})
|> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)

# Business Plan
%Plan{}
|> Plan.changeset(%{
  name: "Business",
  slug: "business",
  max_secret_size_bytes: 10_485_760,
  max_ttl_seconds: 2_592_000,
  max_secrets_per_day: 100_000,
  max_custom_domains: 5,
  max_members: nil,
  custom_branding: true,
  member_auth_on_custom_domain: true,
  admin_on_custom_domain: false,
  member_to_member_sharing: true,
  incoming_secrets: true,
  api_access: true,
  sso_enabled: false,
  audit_log: true
})
|> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)

# Enterprise Plan
%Plan{}
|> Plan.changeset(%{
  name: "Enterprise",
  slug: "enterprise",
  max_secret_size_bytes: 10_485_760,
  max_ttl_seconds: 31_536_000,
  max_secrets_per_day: nil,
  max_custom_domains: nil,
  max_members: nil,
  custom_branding: true,
  member_auth_on_custom_domain: true,
  admin_on_custom_domain: true,
  member_to_member_sharing: true,
  incoming_secrets: true,
  api_access: true,
  sso_enabled: true,
  audit_log: true
})
|> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)

IO.puts("✓ Seeded 4 default plans (free, pro, business, enterprise)")
