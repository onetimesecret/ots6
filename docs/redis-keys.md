# Redis Key Schemas

## Overview

Redis stores ephemeral data with native TTL management. Secrets live in Redis hashes and expire automatically. Timeline sorted sets enable efficient iteration without scanning PostgreSQL.

---

## Connection Pooling

Redix connections are pooled using a simple named connection strategy:

```elixir
# In application.ex supervision tree
children = [
  {Redix, host: "localhost", name: :redix}
]
```

Wrapper modules acquire the connection via `Redix.command(:redix, [...])`.

For production, consider multiple named connections with round-robin selection for higher throughput.

---

## Key Naming Conventions

**Pattern:** `namespace:entity:identifier`

**Rules:**
- Lowercase, colon-separated
- Use UUIDs for entities (accounts, orgs, domains, secrets)
- Consistent ordering: most general → most specific
- No spaces, no special characters beyond colons

**Examples:**
```
secret:a1b2c3d4e5f6              # A specific secret by its key
timeline:org:550e8400-e29b       # Timeline for organization
timeline:account:6ba7b810-9dad   # Timeline for account
```

---

## Secret Hash Structure

**Key pattern:** `secret:{key}`

Where `{key}` is the 22-character base62 URL-safe identifier.

**Hash fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `encrypted_value` | Binary (base64) | Yes | The encrypted payload |
| `encryption_version` | Integer | Yes | Decryption strategy selector (default: 1) |
| `passphrase_required` | Boolean | Yes | Whether passphrase layer exists |
| `organization_id` | UUID | Yes | Owning organization (for entitlements) |
| `custom_domain_id` | UUID | No | Domain context where created |
| `created_by_account_id` | UUID | No | Creator (null for anonymous) |
| `recipient_account_id` | UUID | No | Direct recipient (null for link sharing) |
| `created_at` | Unix timestamp | Yes | Creation time |
| `passphrase_salt` | Binary (base64) | No | Salt for passphrase derivation (if passphrase_required) |

**TTL:** Set on the key itself via `EXPIRE`. When TTL reaches zero, Redis deletes the key automatically.

**Example Redis commands:**

```redis
# Create a secret
HSET secret:abc123xyz encrypted_value "base64blob..."
HSET secret:abc123xyz encryption_version 1
HSET secret:abc123xyz passphrase_required true
HSET secret:abc123xyz organization_id "550e8400-e29b-41d4-a716-446655440000"
HSET secret:abc123xyz created_by_account_id "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
HSET secret:abc123xyz created_at 1705334400
EXPIRE secret:abc123xyz 3600

# Retrieve a secret
HGETALL secret:abc123xyz

# Delete a secret (on reveal or burn)
DEL secret:abc123xyz
```

---

## Timeline Sorted Sets

Timelines enable efficient "recent secrets" queries without full table scans.

**Key patterns:**

| Pattern | Description | Score | Members |
|---------|-------------|-------|---------|
| `timeline:org:{org_id}` | All secrets for an organization | `created_at` timestamp | Secret keys |
| `timeline:domain:{domain_id}` | All secrets for a custom domain | `created_at` timestamp | Secret keys |
| `timeline:account:{account_id}` | All secrets created by an account | `created_at` timestamp | Secret keys |

**Operations:**

**Add to timeline:**
```redis
# When secret is created
ZADD timeline:org:550e8400-e29b 1705334400 abc123xyz
ZADD timeline:account:6ba7b810-9dad 1705334400 abc123xyz
```

**Remove from timeline:**
```redis
# When secret is revealed or expires
ZREM timeline:org:550e8400-e29b abc123xyz
ZREM timeline:account:6ba7b810-9dad abc123xyz
```

**Query recent secrets:**
```redis
# Get 20 most recent secrets for org (highest scores = most recent)
ZREVRANGE timeline:org:550e8400-e29b 0 19 WITHSCORES

# Get secrets in time range (e.g., last 24 hours)
# Score is Unix timestamp, so this gets secrets from yesterday to now
ZRANGEBYSCORE timeline:org:550e8400-e29b 1705248000 1705334400
```

**Cleanup:**

Timeline entries are removed when:
- Secret is revealed (explicit `ZREM`)
- Secret expires naturally (background job scans and prunes)
- Secret is burned (explicit `ZREM`)

A background job periodically scans timelines and removes entries for non-existent secrets:

```elixir
# Pseudo-code
for each timeline key:
  members = ZRANGE timeline:org:xxx 0 -1
  for each member:
    if not EXISTS secret:{member}:
      ZREM timeline:org:xxx member
```

This handles the case where Redis expires a secret but the timeline entry remains.

---

## TTL Strategy

**Secrets:** TTL set directly on the key.
```redis
EXPIRE secret:abc123xyz 3600  # 1 hour
```

When TTL expires, Redis deletes the key automatically. No background jobs needed.

**Receipts (PostgreSQL):** Have their own `receipt_expires_at` column set to 2x the original TTL.

```elixir
# When creating a secret with 3600s TTL:
receipt_expires_at = DateTime.add(created_at, 3600 * 2, :second)
```

This is stored in Postgres and managed by PostgreSQL-side cleanup jobs or queries.

**Timeline entries:** Pruned by background job (see above). Not critical if they lag slightly—queries check secret existence.

---

## Passphrase Handling

When `passphrase_required = true`, the secret has an additional encryption layer.

**Passphrase flow:**

1. **Create:** Server derives key from passphrase using Argon2id, encrypts the payload, stores salt in `passphrase_salt` field.
2. **Reveal:** Client submits passphrase, server derives key from passphrase + stored salt, attempts decryption.
3. **Rate limiting:** After 5 failed passphrase attempts for a given secret key, the secret is auto-destroyed.

**Rate limit tracking:**

Use a separate Redis key:
```
passphrase_attempts:{secret_key} → Integer (TTL matches secret TTL)
```

```redis
# Increment attempt counter
INCR passphrase_attempts:abc123xyz
EXPIRE passphrase_attempts:abc123xyz 3600  # Match secret TTL

# Check attempt count
GET passphrase_attempts:abc123xyz

# If >= 5, destroy secret
DEL secret:abc123xyz
DEL passphrase_attempts:abc123xyz
```

---

## Example Lifecycle

**1. Create secret (authenticated, with passphrase, 1-hour TTL):**

```redis
# Set secret hash
HSET secret:xyz789 encrypted_value "..."
HSET secret:xyz789 encryption_version 1
HSET secret:xyz789 passphrase_required true
HSET secret:xyz789 passphrase_salt "base64salt"
HSET secret:xyz789 organization_id "550e8400-..."
HSET secret:xyz789 custom_domain_id "7c9e6679-..."
HSET secret:xyz789 created_by_account_id "6ba7b810-..."
HSET secret:xyz789 created_at 1705334400
EXPIRE secret:xyz789 3600

# Add to timelines
ZADD timeline:org:550e8400-... 1705334400 xyz789
ZADD timeline:account:6ba7b810-... 1705334400 xyz789
ZADD timeline:domain:7c9e6679-... 1705334400 xyz789
```

**2. Reveal secret:**

```redis
# Retrieve secret
HGETALL secret:xyz789

# After successful passphrase verification and decryption:
# Delete secret
DEL secret:xyz789
DEL passphrase_attempts:xyz789

# Remove from timelines
ZREM timeline:org:550e8400-... xyz789
ZREM timeline:account:6ba7b810-... xyz789
ZREM timeline:domain:7c9e6679-... xyz789
```

**3. Secret expires naturally:**

```redis
# After 3600 seconds, Redis auto-deletes:
# secret:xyz789 → gone
# passphrase_attempts:xyz789 → gone (same TTL)

# Timeline entries remain until background cleanup prunes them
```

---

## Monitoring & Observability

**Metrics to track:**

- `redis.secrets.active` — Current count of secret keys (via `SCAN` or `INFO keyspace`)
- `redis.timeline.size` — Size of each timeline sorted set (via `ZCARD`)
- `redis.memory.used` — Total memory usage
- `redis.keys.expired` — Rate of natural expiration (via `INFO stats`)

**Key patterns for monitoring:**

```redis
# Count secrets
KEYS secret:* | wc -l  # Don't do this in prod! Use SCAN instead

# Timeline sizes
ZCARD timeline:org:550e8400-...

# Memory usage
INFO memory
```

---

## Redis Configuration

**Persistence:** Not required for secrets (ephemeral by design), but recommended for timelines (avoid rebuild on restart).

**Recommended redis.conf:**

```conf
# Append-only file for timeline persistence
appendonly yes
appendfsync everysec

# Max memory policy: evict expired keys first
maxmemory-policy volatile-ttl

# Don't persist RDB snapshots (we don't need them)
save ""
```

This ensures timeline sorted sets survive restarts while allowing Redis to aggressively evict expired secrets.

---

## Migration Path

**From Ruby/Familia to Elixir/Redix:**

The key schemas are identical. The wrapper modules (next document) provide the same interface:

```ruby
# Ruby
secret = Secret.new(key: "abc123")
secret.save
```

```elixir
# Elixir
secret = Secret.Redis.new(key: "abc123")
Secret.Redis.save(secret)
```

Data is cross-compatible. No migration required.
