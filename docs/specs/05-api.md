# API & Tokens

## Overview

The API serves both programmatic access and integrations. It operates in either canonical or custom domain context based on headers. Tokens are PASETO-based with explicit scoping rules.

---

## Context Setting

### Header-Based Context

```
Authorization: Bearer {token}
X-OTS-Domain: secrets.clientco.com  (optional)
```

**Without `X-OTS-Domain`:**
- Canonical context
- Uses token's default organization
- Secrets created with canonical branding

**With `X-OTS-Domain`:**
- Custom domain context
- Domain must exist and be verified
- Token scope must permit access to that domain's organization
- Secrets created with that domain's branding
- Entitlements from that domain's organization

### Context Resolution

```
1. Parse Authorization header
2. Validate token (signature, expiry)
3. If X-OTS-Domain present:
   a. Find CustomDomain by hostname
   b. Verify token has access to domain's organization
   c. Set context = custom_domain, org = domain's org
4. Else:
   a. Set context = canonical
   b. Set org = token's default organization
```

---

## Token Model

### PASETO Structure

Using PASETO v4.local (symmetric encryption) or v4.public (asymmetric signatures).

```
Token:
  id: uuid (jti claim)
  account_id: uuid (sub claim)
  organization_id: uuid (default org)
  domain_scope: 'any' | 'canonical' | [domain_ids]
  permissions: [string] (scopes)
  issued_at: datetime (iat)
  expires_at: datetime (exp)
  issued_by: 'user' | 'oauth' | 'scim'
```

### Token Record (Database)

```
ApiToken
  id: uuid
  account_id: references Account
  organization_id: references Organization
  name: string (user-provided label)
  token_hash: string (for revocation lookup)
  domain_scope: enum ('any', 'canonical', 'specific')
  domain_scope_ids: uuid[] (if specific)
  permissions: string[]
  last_used_at: datetime, nullable
  expires_at: datetime, nullable
  revoked_at: datetime, nullable
  created_at: datetime
```

The actual token is only shown once at creation. Database stores hash for lookup/revocation.

---

## Token Scoping

### The Scope Principle

**Scope contraction only.** Tokens can maintain or narrow scope, never expand.

### Domain Scope Options

**`any`**: Token can access any domain the account has access to.
- For platform users with multiple orgs
- Requires careful handling

**`canonical`**: Token only works in canonical context.
- X-OTS-Domain header is ignored/rejected
- Secrets created have canonical branding

**`specific`**: Token only works for listed domains.
- X-OTS-Domain must match one of domain_scope_ids
- Or canonical if explicitly included

### Permission Scopes

| Scope | Grants |
|-------|--------|
| `secrets:create` | Create secrets |
| `secrets:read` | View secret metadata (not content) |
| `secrets:burn` | Destroy own secrets |
| `activity:read` | View activity log |
| `members:read` | View team directory |
| `members:invite` | Invite new members |
| `domains:read` | View custom domain config |
| `domains:write` | Configure custom domains |
| `admin:read` | View admin settings |
| `admin:write` | Modify admin settings |

### Scope Validation

On each request:
1. Check token has required permission scope
2. Check token domain_scope permits current context
3. Check account still has membership in target org
4. Check membership role permits action

---

## Token Lifecycle

### Creation

Via Workspace App or API:

```
POST /api/v1/tokens
Authorization: Bearer {existing_token_or_session}
Content-Type: application/json

{
  "name": "CI/CD Pipeline",
  "permissions": ["secrets:create", "secrets:read"],
  "domain_scope": "specific",
  "domain_scope_ids": ["domain-uuid-1"],
  "expires_at": "2025-12-31T23:59:59Z"
}
```

Response:
```
{
  "id": "token-uuid",
  "token": "v4.local.xxx...",  // Only shown once!
  "name": "CI/CD Pipeline",
  "permissions": ["secrets:create", "secrets:read"],
  "domain_scope": "specific",
  "domain_scope_ids": ["domain-uuid-1"],
  "expires_at": "2025-12-31T23:59:59Z",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### Listing

```
GET /api/v1/tokens
```

Response shows metadata, never the token value.

### Revocation

```
DELETE /api/v1/tokens/{id}
```

Sets `revoked_at`. Token immediately invalid.

### Rotation

No automatic rotation. User creates new token, updates integrations, revokes old.

---

## API Endpoints

### Secrets

**Create Secret**
```
POST /api/v1/secrets
Authorization: Bearer {token}
X-OTS-Domain: secrets.clientco.com  (optional)
Content-Type: application/json

{
  "value": "the secret content",
  "ttl": 3600,
  "passphrase": "optional"
}
```

Response:
```
{
  "key": "abc123xyz",
  "url": "https://secrets.clientco.com/secret/abc123xyz",
  "expires_at": "2024-01-15T11:30:00Z",
  "passphrase_required": true
}
```

**Get Secret Metadata**
```
GET /api/v1/secrets/{key}
```

Response:
```
{
  "key": "abc123xyz",
  "created_at": "2024-01-15T10:30:00Z",
  "expires_at": "2024-01-15T11:30:00Z",
  "passphrase_required": true,
  "revealed": false
}
```

Does NOT return secret content. Use reveal endpoint.

**Reveal Secret** (consumes it)
```
POST /api/v1/secrets/{key}/reveal
Content-Type: application/json

{
  "passphrase": "if required"
}
```

Response:
```
{
  "value": "the secret content",
  "revealed_at": "2024-01-15T10:45:00Z"
}
```

**Burn Secret**
```
DELETE /api/v1/secrets/{key}
```

Response:
```
{
  "burned": true,
  "burned_at": "2024-01-15T10:40:00Z"
}
```

### Activity

**List Activity**
```
GET /api/v1/activity?limit=25&after={cursor}
```

Response:
```
{
  "entries": [
    {
      "id": "entry-uuid",
      "action": "secret_created",
      "created_at": "2024-01-15T10:30:00Z",
      "metadata": {
        "ttl_seconds": 3600,
        "passphrase_used": true
      }
    }
  ],
  "pagination": {
    "next_cursor": "xxx",
    "has_more": true
  }
}
```

### Members

**List Members**
```
GET /api/v1/members
```

**Invite Member**
```
POST /api/v1/members/invite
Content-Type: application/json

{
  "email": "newuser@example.com",
  "role": "member"
}
```

### Domains

**List Domains**
```
GET /api/v1/domains
```

**Get Domain**
```
GET /api/v1/domains/{id}
```

**Update Domain**
```
PATCH /api/v1/domains/{id}
Content-Type: application/json

{
  "brand_name": "ClientCo Secure",
  "public_homepage": true
}
```

### Account

**Get Current Account**
```
GET /api/v1/account
```

Response:
```
{
  "id": "account-uuid",
  "email": "user@example.com",
  "display_name": "Jane Doe",
  "organizations": [
    {
      "id": "org-uuid",
      "name": "Acme Corp",
      "role": "admin"
    }
  ]
}
```

---

## Error Responses

### Standard Error Format

```
{
  "error": {
    "code": "invalid_token",
    "message": "The provided token is invalid or expired",
    "details": {}
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `invalid_token` | 401 | Token missing, malformed, or expired |
| `insufficient_scope` | 403 | Token lacks required permission |
| `domain_access_denied` | 403 | Token doesn't permit this domain |
| `not_found` | 404 | Resource doesn't exist |
| `already_revealed` | 410 | Secret already consumed |
| `validation_error` | 422 | Invalid input |
| `rate_limited` | 429 | Too many requests |
| `internal_error` | 500 | Server error |

### Rate Limiting Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705315200
```

---

## Rate Limits

Plan-based rate limits:

| Plan | Requests/hour | Secrets/day |
|------|---------------|-------------|
| Free | — (no API) | — |
| Pro | 1,000 | 100 |
| Business | 10,000 | 1,000 |
| Enterprise | 100,000 | unlimited |

Per-endpoint limits may also apply (e.g., 10 reveals/minute to prevent enumeration).

---

## Webhook Integration

For event notifications (Business+):

### Configuration

```
POST /api/v1/webhooks
Content-Type: application/json

{
  "url": "https://example.com/webhook",
  "events": ["secret.revealed", "secret.expired"],
  "secret": "webhook-signing-secret"
}
```

### Events

| Event | Payload |
|-------|---------|
| `secret.created` | key, created_at, expires_at |
| `secret.revealed` | key, revealed_at |
| `secret.expired` | key, expired_at |
| `secret.burned` | key, burned_at |
| `member.invited` | email, role |
| `member.joined` | account_id, role |

### Payload Format

```
POST {webhook_url}
Content-Type: application/json
X-OTS-Signature: sha256={signature}

{
  "event": "secret.revealed",
  "timestamp": "2024-01-15T10:45:00Z",
  "data": {
    "key": "abc123xyz",
    "revealed_at": "2024-01-15T10:45:00Z"
  }
}
```

Signature computed as HMAC-SHA256 of body with webhook secret.

---

## SDK Patterns

### Token Header

```
Authorization: Bearer v4.local.xxx...
```

### Domain Context Header

```
X-OTS-Domain: secrets.clientco.com
```

### Common Patterns

**Create and share:**
```python
secret = ots.secrets.create(
    value="sensitive data",
    ttl=3600,
    domain="secrets.clientco.com"
)
print(secret.url)  # Share this link
```

**Check if revealed:**
```python
secret = ots.secrets.get("abc123xyz")
if secret.revealed:
    print("Already viewed")
else:
    print(f"Expires at {secret.expires_at}")
```

**Burn if unused:**
```python
try:
    ots.secrets.burn("abc123xyz")
    print("Destroyed")
except NotFoundError:
    print("Already revealed or expired")
```

---

## SCIM Integration (Enterprise)

For directory sync with identity providers.

### Endpoints

```
GET    /scim/v2/Users
POST   /scim/v2/Users
GET    /scim/v2/Users/{id}
PATCH  /scim/v2/Users/{id}
DELETE /scim/v2/Users/{id}
GET    /scim/v2/Groups
```

### Authentication

SCIM uses Bearer token with `scim:*` scope.

### User Provisioning

SCIM creates/updates Account and Membership:
- Account created if email doesn't exist
- Membership created in the org that owns the SCIM token
- Domain scope applied based on group membership

### Deprovisioning

SCIM DELETE removes Membership, not Account (account may belong to other orgs).

---

## Versioning

API version in URL path: `/api/v1/...`

### Version Policy

- v1 remains stable
- Breaking changes require new version
- Deprecation notice: 6 months minimum
- Multiple versions supported simultaneously

### Version Header (optional)

```
X-OTS-API-Version: 2024-01-15
```

For requesting specific behavior within a version (date-based, like Stripe).
