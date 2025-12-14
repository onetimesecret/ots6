# OneTimeSecret Phoenix: Implementation Plan

## Overview

This plan breaks the build into six phases, each with concrete deliverables, dependencies, and validation criteria. Phases build on each other—later phases assume earlier phases are complete and validated.

**Effort Scale:**
- **S (Small):** 1-2 days
- **M (Medium):** 3-5 days
- **L (Large):** 1-2 weeks

---

## Phase 1: Foundation

**Goal:** Database setup, core schemas, Redis integration, basic infrastructure.

### Deliverables

**1.1 Database Migrations** (M)
- Create all Ecto migrations in correct order:
  - `plans`
  - `accounts`
  - `organizations`
  - `custom_domains`
  - `memberships`
  - `secret_receipts`
  - `sessions`
- Seed default plans (free, pro, business, enterprise)
- Validate all foreign key constraints

**1.2 Ecto Schemas** (M)
- Implement all schema modules with associations
- Add changesets with validations
- Test associations and constraints

**1.3 Redis Integration** (M)
- Add `redix` dependency
- Configure Redix connection pool in supervision tree
- Create `OneTimeSecret.Redis` base module
- Implement connection pooling strategy (named connections or Poolboy)
- Test Redis connectivity and basic operations

**1.4 Context Modules** (S)
- `OneTimeSecret.Accounts` - account CRUD
- `OneTimeSecret.Organizations` - org and membership CRUD
- `OneTimeSecret.Plans` - plan queries
- `OneTimeSecret.CustomDomains` - domain CRUD
- Basic functions only, no business logic yet

**1.5 Personal Org Auto-Creation** (S)
- Implement `Accounts.register_user/1` with Ecto.Multi
- Auto-create personal org + owner membership on signup
- Validate atomicity (rollback on failure)

### Dependencies
- None (this is the foundation)

### Validation Criteria
- [ ] All migrations run cleanly (`mix ecto.migrate`)
- [ ] Can create account + personal org in single transaction
- [ ] All foreign key constraints enforced
- [ ] Redis connection pool works, handles connection failures gracefully
- [ ] Seeds create all four plans with correct entitlements

### Effort Estimate: **L (1.5 weeks)**

---

## Phase 2: Secret App

**Goal:** The core transit operation—create, reveal, destroy. High-traffic path, Redis-backed.

### Deliverables

**2.1 Redis Secret Module** (M)
- `OneTimeSecret.Secrets.Redis` Familia-style wrapper
- Key generation (22-char base62)
- Secret hash CRUD operations
- TTL management
- Timeline sorted set operations (add, remove, query)

**2.2 Encryption Module** (M)
- `OneTimeSecret.Crypto` for encryption operations
- Server-side encryption (AES-256-GCM)
- Per-secret key derivation from master key + secret ID
- Passphrase layer (Argon2id with salt)
- Support `encryption_version` for key rotation

**2.3 Secret Receipt Module** (S)
- `OneTimeSecret.Secrets.Receipt` context
- Create receipt on secret creation (2x TTL)
- Update receipt on reveal (timestamp, IP)
- Query receipts for activity feed

**2.4 Create Secret Flow** (M)
- Anonymous creation on canonical domain
- Authenticated creation with org entitlements
- Validate against plan limits (size, TTL, daily quota)
- Store in Redis + create receipt in Postgres
- Add to timeline sorted sets

**2.5 Reveal Secret Flow** (M)
- Fetch from Redis by key
- Passphrase verification (if required)
- Rate limiting on passphrase attempts (5 max, then destroy)
- Decrypt and display
- Destroy secret from Redis, remove from timelines
- Update receipt with reveal timestamp/IP

**2.6 LiveView UIs** (L)
- `SecretLive.New` - create form with TTL/passphrase options
- `SecretLive.Show` - reveal page (before decryption)
- `SecretLive.Revealed` - decrypted content display
- Styling with Tailwind (clean, minimal)

**2.7 Branding Support** (S)
- Pass `custom_domain` context to templates
- Render with tenant branding (brand_name, logo_url, primary_color)
- Fallback to OTS branding if `custom_domain_id` is null

### Dependencies
- Phase 1 (Foundation) complete
- Redis connection pool operational
- `secret_receipts` table exists

### Validation Criteria
- [ ] Can create anonymous secret on canonical domain
- [ ] Can create authenticated secret with org entitlements enforced
- [ ] Secret auto-expires after TTL (verify with short TTL test)
- [ ] Reveal works, secret destroyed immediately after
- [ ] Passphrase protection works, rate limiting triggers after 5 failures
- [ ] Receipts created and updated correctly
- [ ] Timeline sorted sets updated on create/reveal

### Effort Estimate: **L (2 weeks)**

---

## Phase 3: Session App

**Goal:** Authentication, MFA, domain-scoped sessions, login/logout flows.

### Deliverables

**3.1 Password Hashing** (S)
- Add `bcrypt_elixir` dependency
- Implement password hashing in `Account` schema
- Validate password strength (min 12 chars)

**3.2 Session Management** (M)
- `OneTimeSecret.Sessions` context
- Create session on login (canonical vs custom domain context)
- Session validation plug
- Sliding expiration (configurable TTL)
- Session cookie scoping (domain-specific)

**3.3 Login/Logout Flows** (M)
- `SessionLive.New` - login form
- `SessionController.create` - authenticate and create session
- `SessionController.delete` - logout, clear session
- CSRF protection (Phoenix built-in)

**3.4 MFA (TOTP)** (M)
- Add `:nimble_totp` dependency
- `Accounts.enable_totp/1` - generate secret, return QR code data
- `Accounts.verify_totp/2` - validate TOTP code
- Pending auth state in Redis (5-minute TTL)
- `SessionLive.MFA` - TOTP verification step

**3.5 Recovery Codes** (S)
- Generate 10 recovery codes on MFA enable
- Store hashed in `accounts.recovery_codes` JSONB field
- One-time use, mark as consumed

**3.6 Password Reset** (M)
- Signed token with 1-hour expiry
- `SessionLive.ForgotPassword` - request form
- `SessionLive.ResetPassword` - reset form with token
- Email delivery via Swoosh (local dev: mailbox preview)

**3.7 Email Verification** (S)
- Signed token, send on registration and email change
- `SessionController.verify_email` - token validation endpoint
- Set `email_verified_at` on success

### Dependencies
- Phase 1 (Foundation) complete
- Redis for pending MFA state
- Swoosh configured for email delivery

### Validation Criteria
- [ ] Can register account, receive verification email
- [ ] Can log in with email + password
- [ ] Session persists across requests (sliding expiration works)
- [ ] Logout clears session
- [ ] MFA setup works, TOTP validation required on subsequent logins
- [ ] Recovery codes work, single-use enforced
- [ ] Password reset flow works end-to-end
- [ ] Domain-scoped sessions work (canonical vs custom domain cookies)

### Effort Estimate: **L (1.5 weeks)**

---

## Phase 4: Workspace App

**Goal:** Dashboard, activity feed, team directory, settings. Member-facing UI.

### Deliverables

**4.1 Dashboard LiveView** (M)
- `WorkspaceLive.Dashboard` - landing page after login
- Show active organization context
- Org switcher (for multi-org accounts)
- Quick stats (secrets created this week, team size)

**4.2 Activity Feed** (M)
- Query `secret_receipts` filtered by org
- Show recent secrets (created, revealed, expired)
- Paginate with cursor-based pagination
- Real-time updates via PubSub (optional, nice-to-have)

**4.3 Team Directory** (S)
- List memberships for active org
- Show role, provisioned_via, joined_at
- Admin can change roles (owner/admin only)

**4.4 Invite Members** (M)
- `WorkspaceLive.InviteForm` - email + role selector
- Generate signed invite token (7-day expiry)
- Send invitation email
- `SessionLive.AcceptInvite` - token redemption, create membership

**4.5 Personal Settings** (S)
- `WorkspaceLive.Settings` - display name, locale, timezone
- Change email (requires re-verification)
- Change password (requires current password)
- MFA enable/disable

**4.6 Organization Settings** (M)
- `WorkspaceLive.OrgSettings` - org name, slug
- Plan display (read-only for now, billing later)
- Custom domain list (if any)
- Delete org (owner only, with confirmation)

**4.7 Session Management** (S)
- `WorkspaceLive.Sessions` - list active sessions
- Show IP, user agent, last active
- Revoke session (delete from DB)

### Dependencies
- Phase 1 (Foundation) complete
- Phase 3 (Session App) complete (for authentication)
- `secret_receipts` for activity feed
- Email delivery for invitations

### Validation Criteria
- [ ] Dashboard loads, shows correct org context
- [ ] Activity feed shows recent secrets
- [ ] Org switcher works for multi-org accounts
- [ ] Can invite member, they receive email, accept invite creates membership
- [ ] Team directory shows all members with correct roles
- [ ] Can update personal settings
- [ ] Can update org settings (name, slug)
- [ ] Can revoke active sessions

### Effort Estimate: **L (1.5 weeks)**

---

## Phase 5: Custom Domains

**Goal:** Domain resolution, verification, branding, context switching.

### Deliverables

**5.1 Domain Detection Plug** (M)
- `OneTimeSecret.Plugs.DomainContext`
- Extract hostname from request
- Query `custom_domains` where `hostname = ? AND verified_at IS NOT NULL`
- Set context in `conn.assigns`:
  - `:context_type` (`:canonical` or `:custom_domain`)
  - `:custom_domain` (record or nil)
  - `:organization` (from domain or session)
  - `:plan` (from organization)
- Add to router pipeline

**5.2 Domain Verification** (M)
- `CustomDomains.verify_domain/1` - DNS TXT record check
- Use `:inet_res` or external DNS API
- Set `verified_at` on success
- `WorkspaceLive.Domains` - domain management UI
- Show verification instructions and status

**5.3 Branding Application** (S)
- Update layouts to use `@custom_domain` branding
- Inject `brand_name`, `logo_url`, `primary_color`
- Conditional CSS injection (Enterprise only, CSP-safe)

**5.4 Mode Availability Checks** (M)
- `OneTimeSecret.Entitlements` module
- Check plan flags against context
- Enforce mode restrictions:
  - Sender: `public_homepage` or `anonymous_create` or authenticated
  - Member: `member_auth_on_custom_domain` entitlement
  - Admin: `admin_on_custom_domain` entitlement
- Redirect or 403 if unauthorized

**5.5 Domain-Scoped Authentication** (M)
- Custom domain login creates session with `context_type = :custom_domain`
- Validate `membership.domain_scope_id` matches current domain
- Prevent cross-domain session reuse

**5.6 Cross-Domain Secret Access** (S)
- Implement Option B (brand-aware rendering on any domain)
- Reveal page works on canonical or custom domain
- Branding from `secret.custom_domain_id`
- Dashboard routes enforce strict context (redirect if mismatch)

### Dependencies
- Phase 1 (Foundation) complete
- Phase 2 (Secret App) complete (for branding on reveal)
- Phase 3 (Session App) complete (for domain-scoped auth)
- Phase 4 (Workspace App) complete (for domain management UI)

### Validation Criteria
- [ ] Domain detection works, sets correct context
- [ ] Can add custom domain, verify DNS, domain becomes active
- [ ] Branding applied on custom domain (logo, colors, brand name)
- [ ] Mode restrictions enforced (anonymous can't access member features)
- [ ] Domain-scoped sessions work, prevent cross-domain reuse
- [ ] Secret reveal works on both canonical and custom domain with correct branding
- [ ] Dashboard on wrong domain redirects to correct domain

### Effort Estimate: **L (1.5 weeks)**

---

## Phase 6: API

**Goal:** Token model, PASETO tokens, API endpoints, rate limiting, webhooks.

### Deliverables

**6.1 API Token Schema** (S)
- `OneTimeSecret.API.Token` Ecto schema
- Fields: `name`, `scopes`, `token_hash`, `last_used_at`, `expires_at`
- Belongs to account and organization

**6.2 PASETO Token Generation** (M)
- Add `:paseto` dependency
- `OneTimeSecret.API.PASETO` module
- Generate v4.local tokens with claims:
  - `sub` (account_id)
  - `org` (organization_id)
  - `jti` (unique token ID)
  - `scopes` (array of scope strings)
  - `exp` (expiry timestamp)
- Sign with symmetric key from environment

**6.3 Token Management UI** (S)
- `WorkspaceLive.APITokens` - list tokens
- Create new token form (name, scopes, expiry)
- Revoke token (delete from DB)
- Show token once on creation (can't retrieve later)

**6.4 API Authentication Plug** (M)
- `OneTimeSecret.Plugs.APIAuth`
- Extract token from `Authorization: Bearer <token>` header
- Verify PASETO signature and expiry
- Lookup `token_hash` in DB (for revocation check)
- Load account, org, plan into `conn.assigns`
- Handle `X-OTS-Domain` header for custom domain context

**6.5 Rate Limiting** (M)
- Add `:hammer` or `:ex_rated` dependency
- Rate limit by token ID (plan-specific limits)
- Redis-backed rate limit counters
- Return `429 Too Many Requests` with `Retry-After` header

**6.6 Core API Endpoints** (L)
- `POST /api/v1/secrets` - create secret
- `GET /api/v1/secrets/:key` - reveal secret (destroys)
- `GET /api/v1/activity` - list receipts (paginated)
- `GET /api/v1/members` - list org members
- JSON responses, proper error handling
- OpenAPI spec generation (via `open_api_spex`)

**6.7 Webhook System** (M)
- `OneTimeSecret.Webhooks.Subscription` schema
- Register webhook URLs per organization
- Events: `secret.created`, `secret.revealed`
- Async delivery via `Broadway` or `Oban`
- Retry with exponential backoff
- Signature verification (HMAC-SHA256)

**6.8 SCIM Endpoints** (L) [OPTIONAL]
- Defer to Phase 7 or later
- Requires deep understanding of SCIM spec
- Provisioning/deprovisioning users via SCIM

### Dependencies
- Phase 1 (Foundation) complete
- Phase 3 (Session App) complete (for account/org context)
- Phase 4 (Workspace App) complete (for token management UI)
- Redis for rate limiting

### Validation Criteria
- [ ] Can create API token, receive PASETO token
- [ ] Token auth works, sets correct context
- [ ] Rate limiting enforced, returns 429 on excess
- [ ] Can create secret via API
- [ ] Can reveal secret via API (destroys secret)
- [ ] Activity endpoint returns receipts
- [ ] Members endpoint returns org members
- [ ] Webhook subscription works, delivers events
- [ ] Webhook retries on failure
- [ ] OpenAPI spec generated and accurate

### Effort Estimate: **L (2 weeks, or 1 week without webhooks)**

---

## Additional Phases (Deferred)

### Phase 7: Colonel App (Platform Operations)
- Operator dashboard
- Organization search and impersonation
- Plan management (create, edit plans)
- Usage analytics
- Dangerous operations (delete org, purge secrets)
- Audit log viewer

**Effort:** M-L (1 week)

### Phase 8: Production Hardening
- PostgreSQL configuration (production)
- Redis clustering/HA
- Secrets management (master key rotation)
- Monitoring and alerting (Prometheus, Grafana)
- Log aggregation (ELK, Datadog)
- CDN integration for static assets
- Rate limiting at edge (Cloudflare, Fastly)

**Effort:** L (1-2 weeks)

### Phase 9: Advanced Features
- SSO/SCIM provisioning (Enterprise)
- Incoming secrets (Business+)
- Member-to-member sharing (Business+)
- Custom CSS injection (Enterprise, CSP-reviewed)
- Audit log (detailed event tracking)

**Effort:** L+ (2+ weeks depending on scope)

---

## Summary Timeline

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| 1. Foundation | L (1.5 weeks) | None |
| 2. Secret App | L (2 weeks) | Phase 1 |
| 3. Session App | L (1.5 weeks) | Phase 1 |
| 4. Workspace App | L (1.5 weeks) | Phase 1, 3 |
| 5. Custom Domains | L (1.5 weeks) | Phase 1, 2, 3, 4 |
| 6. API | L (2 weeks) | Phase 1, 3, 4 |

**Total Core MVP:** ~10 weeks (2.5 months)

**With Colonel + Hardening:** ~13 weeks (3 months)

---

## Validation Strategy

After each phase:
1. **Manual testing** - Walk through all user flows
2. **Automated tests** - Write tests for critical paths
3. **Load testing** - Stress test high-traffic paths (Secret App especially)
4. **Security review** - Check for common vulnerabilities (XSS, CSRF, injection, etc.)
5. **Documentation** - Update README, API docs, deployment guides

---

## Risk Mitigation

**High-Risk Areas:**
- **Secret lifecycle** - Must be bulletproof (no leaks, guaranteed destruction)
- **Encryption** - Key management, rotation, secure defaults
- **Rate limiting** - Prevent abuse without false positives
- **Domain verification** - DNS-based, vulnerable to subdomain takeover
- **Session security** - Cookie scoping, CSRF, XSS

**Mitigation:**
- Thorough testing for secret lifecycle
- Security review by external party before launch
- Rate limiting tuned with real-world data
- Domain verification with clear instructions and warnings
- Follow Phoenix security best practices

---

## Next Steps

1. Review and approve this plan
2. Begin Phase 1 (Foundation)
3. Iterate on phases as we learn

