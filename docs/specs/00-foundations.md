# OneTimeSecret Phoenix: Foundations

## What This Is

OneTimeSecret is a **secrets transit platform**. Secrets are created, shared via link, revealed once, then destroyed. The lifecycle is:

**create → share link → recipient opens → gone**

There is no persistent inventory. No folders, projects, or workspaces for organizing secrets because there's nothing persistent to organize. This informs every architectural decision.

---

## Two Delivery Addresses

The platform has two parallel entry points. These aren't "platform + feature"—they're two instances of the same architectural pattern:

|                      | Canonical                | Custom Domain              |
|----------------------|--------------------------|----------------------------|
| **Address**          | onetimesecret.com        | secrets.clientco.com       |
| **Brand**            | OTS                      | ClientCo (white-label)     |
| **User population**  | Platform users           | Tenant users               |
| **Context**          | Multi-org capable        | Single org scoped          |

Custom domains aren't a feature you bolt on. They *are* the product for tenant users. The delivery address determines brand, context, and available modes.

### What Determines What

**Context** is where you're doing something (determined by domain):
- Canonical context: Platform-branded, multi-org capable
- Custom domain context: Tenant-branded, single org scoped

**Mode** is what you're doing (capability/perspective):
- Recipient: Revealing a secret
- Sender: Creating a secret
- Member: Activity feed, team sharing
- Admin: Settings, user management, billing

Domain does not determine mode. Entitlements gate which modes surface in which context.

---

## Three User Populations

### Platform Users (Canonical Domain)

- Know they're using OTS
- Manage orgs, billing, custom domains
- Work across multiple contexts
- Access canonical domain directly

### Tenant Users (Custom Domain Only)

- Know they're using "ClientCo Secure Share"
- Never see onetimesecret.com
- One context: their employer's
- May be provisioned via SSO/SCIM, never having touched OTS directly
- Their `domain_scope` locks them to a specific custom domain

### Recipients (Transient)

- Following a link to reveal a secret
- Brand-aware based on link origin
- May or may not be familiar with OTS
- No account required, no authentication

---

## Four Apps

The platform consists of four apps with clear boundaries. Each has a distinct purpose and serves specific user populations.

### Secret App (Transactional)

**Purpose**: The transit operation—create, share, reveal, destroy.

**Serves**: Creators (anonymous or authenticated), Recipients

**Characteristics**:
- Create form, reveal page, confirmation
- The *only* part that gets white-labeled
- Lightweight, high-performance—this is the high-traffic path
- Minimal state, minimal dependencies

**Surfaces at**: Both canonical and custom domains (subject to entitlements)

### Workspace App (Management)

**Purpose**: Account holder workspace for managing their stuff.

**Serves**: Authenticated account holders

**Characteristics**:
- Activity feed, team directory, settings, billing
- Always authenticated
- OTS-branded, except Enterprise domain-scoped admin sees tenant branding
- Organization context aware (canonical shows org switcher for multi-org accounts)

**Surfaces at**: Canonical (always), custom domains (Business+ tiers)

### Colonel App (System)

**Purpose**: Platform oversight and dangerous operations.

**Serves**: OTS operators only

**Characteristics**:
- Utilitarian UI, raw data views
- Safety rails on destructive operations
- Never surfaces on custom domains

**Surfaces at**: Internal/operator access only

### Session App (Gateway)

**Purpose**: Authentication boundary crossing.

**Serves**: Everyone transitioning between anonymous and authenticated states

**Characteristics**:
- Login, logout, MFA, password reset, token refresh
- Standalone module—cares about credentials and tokens, not secrets or dashboards
- Minimal layout (neither marketing nor dashboard chrome)
- Domain-aware: canonical sessions vs custom domain sessions

**Surfaces at**: Both canonical and custom domains (where authentication is enabled)

---

## Data Models

### Account

The identity. One human, one account, regardless of how many organizations they belong to.

```
Account
  id: uuid
  email: string, unique
  email_verified_at: datetime, nullable
  password_hash: string, nullable (for SSO-only accounts)
  totp_secret: string, nullable
  display_name: string, nullable
  locale: string, default "en"
  timezone: string, nullable
  created_at: datetime
  updated_at: datetime
```

### Organization

The billing and entitlement holder. Every account has at least one organization.

```
Organization
  id: uuid
  name: string
  slug: string, unique
  plan_id: references Plan
  owner_account_id: references Account
  personal: boolean, default false
  metadata: jsonb
  created_at: datetime
  updated_at: datetime
```

The `personal` flag indicates an implicit single-member org that the user may not be aware of. Created automatically on account signup. This eliminates "orgless" accounts and the branching logic they require.

### Membership

Connects accounts to organizations with role and optional domain scoping.

```
Membership
  id: uuid
  account_id: references Account
  organization_id: references Organization
  role: enum (owner, admin, member), default "member"
  domain_scope_id: references CustomDomain, nullable
  provisioned_via: enum (invite, sso, scim), default "invite"
  joined_at: datetime
  created_at: datetime
  updated_at: datetime

  unique constraint: [account_id, organization_id]
```

**The `domain_scope_id` field answers "where does this user live":**
- `null` = Platform user. Accesses canonical domain, sees all org's custom domains.
- `domain_id` = Tenant user. Locked to that domain. Canonical doesn't exist for them.

### CustomDomain

A branded entry point to the platform, owned by an organization.

```
CustomDomain
  id: uuid
  organization_id: references Organization
  hostname: string, unique
  verified_at: datetime, nullable
  verification_token: string
  
  # Branding
  brand_name: string, nullable
  logo_url: string, nullable
  primary_color: string, nullable
  custom_css: text, nullable
  
  # Mode settings
  public_homepage: boolean, default false
  anonymous_create: boolean, default false
  incoming_secrets_email: string, nullable
  
  created_at: datetime
  updated_at: datetime
```

**Mode settings explained:**
- `public_homepage`: When true, shows create form to visitors. When false, shows splash/"internal use" message.
- `anonymous_create`: When true, visitors can create secrets without authenticating.
- `incoming_secrets_email`: Enables incoming secrets feature—secrets created are auto-delivered to this address.

### Secret

Ephemeral by design. Belongs to an organization (for entitlement checking and audit), created in a context.

```
Secret
  id: uuid
  key: string, unique, nullable (the URL-safe identifier; null for direct sharing)
  organization_id: references Organization
  custom_domain_id: references CustomDomain, nullable
  created_by_account_id: references Account, nullable
  recipient_account_id: references Account, nullable
  
  # Encrypted payload
  encrypted_value: binary
  encryption_version: integer, default 1
  
  # Lifecycle
  passphrase_required: boolean, default false
  ttl_seconds: integer
  expires_at: datetime
  revealed_at: datetime, nullable
  revealed_by_ip: string, nullable
  
  created_at: datetime
```

**Context fields:**
- `custom_domain_id`: Which domain context this was created in (affects branding on reveal page)
- `created_by_account_id`: Null for anonymous creation
- `recipient_account_id`: For member-to-member sharing (no link generated, recipient notified)

Secrets are hard-deleted after reveal or expiry. No soft deletes—data is gone.

### Plan

Defines entitlements for an organization.

```
Plan
  id: uuid
  name: string
  slug: string, unique (free, pro, business, enterprise)
  
  # Limits
  max_secret_size_bytes: integer
  max_ttl_seconds: integer
  max_secrets_per_day: integer, nullable (null = unlimited)
  max_custom_domains: integer, default 0
  max_members: integer, nullable (null = unlimited)
  
  # Feature flags
  custom_branding: boolean, default false
  member_auth_on_custom_domain: boolean, default false
  admin_on_custom_domain: boolean, default false
  member_to_member_sharing: boolean, default false
  incoming_secrets: boolean, default false
  api_access: boolean, default false
  sso_enabled: boolean, default false
  audit_log: boolean, default false
  
  created_at: datetime
  updated_at: datetime
```

### Session

Tracks authenticated state and active context.

```
Session
  id: uuid
  account_id: references Account
  context_type: enum (canonical, custom_domain)
  custom_domain_id: references CustomDomain, nullable
  active_organization_id: references Organization
  active_custom_domain_id: references CustomDomain, nullable
  ip_address: string
  user_agent: string
  created_at: datetime
  expires_at: datetime
```

**Context tracking:**
- `context_type` + `custom_domain_id`: Where this session lives
- `active_organization_id`: Which org's entitlements apply
- `active_custom_domain_id`: Which domain's branding appears on created secrets (canonical context only—allows selecting from dropdown)

---

## Tier Progression

Custom domain capability unlocks progressively:

| Tier | Custom domain is... | What surfaces there | OTS visibility |
|------|---------------------|---------------------|----------------|
| **Free** | — | — | Full |
| **Pro** | Delivery address | Recipient branding only | Full |
| **Business** | Workspace for members | Auth, create, activity | Partial (billing on canonical) |
| **Enterprise** | Self-contained product | Everything including admin | None (invisible plumbing) |
| **Enterprise Plus** | Dedicated install | Everything, isolated DB | Infrastructure only |
| **Self-hosted** | Customer's deployment | Everything | N/A |

### Entitlement Matrix

| Feature | Free | Pro | Business | Enterprise |
|---------|------|-----|----------|------------|
| Custom domains | 0 | 1 | 5 | unlimited |
| Custom branding | — | ✓ | ✓ | ✓ |
| Member auth on custom domain | — | — | ✓ | ✓ |
| Admin on custom domain | — | — | — | ✓ |
| Member-to-member sharing | — | — | ✓ | ✓ |
| Incoming secrets | — | — | ✓ | ✓ |
| SSO/SCIM | — | — | — | ✓ |
| Audit log | — | ✓ | ✓ | ✓ |
| API access | — | ✓ | ✓ | ✓ |

---

## Scope Rules

### The Scope Principle

**Scope contraction only.** Domain-scoped memberships and domain-restricted tokens can only maintain or narrow scope, never expand. To broaden access, revoke and recreate.

### Entitlement Checking

Every capability check follows this path:

```
account → active membership → organization → plan → entitlement flag
```

For custom domain context, the membership must either:
- Have `domain_scope_id` matching current domain, or
- Have `domain_scope_id` null (can access any domain in org)

### Domain-Scoped Users

When `membership.domain_scope_id` is set:
- That account cannot access canonical workspace
- That domain is their entire experience
- They see tenant branding, not OTS branding
- They may have been provisioned via SSO/SCIM and never touched OTS directly

---

## Mode Availability by Context

### Canonical Context

| Mode | Available | Requirements |
|------|-----------|--------------|
| Recipient | Always | — |
| Sender | Always | — |
| Member | Authenticated | Account with membership |
| Admin | Authenticated | Admin or owner role |

Full platform access. Multi-org support with org switcher. All apps surface.

### Custom Domain Context

| Mode | Available | Requirements |
|------|-----------|--------------|
| Recipient | Always | — |
| Sender | Conditional | `public_homepage` or `anonymous_create` or authenticated |
| Member | Plan-gated | `member_auth_on_custom_domain` entitlement |
| Admin | Plan-gated | `admin_on_custom_domain` entitlement |

Single org scoped. No org switcher. Branding from CustomDomain config.

---

## Domain Verification

Custom domains must be verified before activation:

1. Organization adds hostname to their account
2. System generates verification token
3. Organization adds TXT record: `_onetimesecret.{hostname}` → token
4. System verifies DNS, sets `verified_at`
5. Domain becomes active

---

## Member-to-Member Sharing

Business+ feature. Secrets shared directly between organization members without generating a link.

**Flow:**
1. Sender selects recipient from member directory
2. Secret created with `recipient_account_id` set, `key` is null
3. Recipient notified (email and/or in-app)
4. Recipient logs in, sees pending secret in dashboard
5. Recipient reveals, secret destroyed

This keeps the secret entirely within the organization context—no link to leak.

---

## Incoming Secrets

Business+ feature. A custom domain receives secrets from external parties, delivered to a configured email.

**Configuration:** Set `incoming_secrets_email` on CustomDomain.

**Flow:**
1. External party visits custom domain
2. Creates secret via incoming secrets form
3. Secret created, immediate notification sent to configured email
4. Email contains link to reveal (one-time, as normal)

Useful for receiving sensitive information from clients, candidates, vendors.

---

## Audit Log

For plans with `audit_log` enabled:

```
AuditEntry
  id: uuid
  organization_id: references Organization
  account_id: references Account, nullable
  action: enum (secret_created, secret_revealed, member_invited, ...)
  target_type: string
  target_id: uuid
  metadata: jsonb
  ip_address: string
  created_at: datetime
```

---

## Areas Requiring Separate Documents

The following topics have their own specification documents:

- **Routing & Context** (`01-routing.md`): Domain detection, context setting, request flow
- **Secret App** (`02-secret-app.md`): Create, share, reveal, destroy flows; branding mechanics
- **Workspace App** (`03-workspace-app.md`): Activity, team, settings; tier-gated features
- **Session App** (`04-session-app.md`): Auth flows, MFA, token lifecycle
- **API & Tokens** (`05-api.md`): Token model, PASETO structure, scoping, endpoints
- **Colonel App** (`06-colonel.md`): Platform operations, safety rails

---

## Deferred (Understood, Building Later)

These features are architecturally understood but not blocking v1:

- **SSO/SCIM provisioning**: Enterprise tier, requires identity provider integration
- **Incoming secrets**: Business+ tier, requires notification infrastructure
- **Member-to-member sharing**: Business+ tier, requires notification infrastructure
- **Enterprise Plus / Dedicated**: Isolated database deployment model
- **Custom CSS injection**: Security review required

The architecture accommodates these—they're not being "added later" but rather "implemented when scheduled."
