# Routing & Context

## Overview

Every request starts with domain detection. The hostname determines context, which determines available modes, which determines what UI surfaces.

---

## Domain Detection Flow

```
incoming request
    │
    ├─ hostname matches verified CustomDomain record?
    │   ├─ yes: Custom domain context
    │   │   └─ load CustomDomain → Organization → Plan
    │   │   └─ set available modes based on plan entitlements
    │   │
    │   └─ no: Canonical context
    │       └─ full platform access
    │       └─ active org from session (if authenticated)
```

### Resolution Order

1. Extract hostname from request
2. Query CustomDomain where `hostname = ?` and `verified_at IS NOT NULL`
3. If found: custom domain context with that domain's org and plan
4. If not found: canonical context

Unverified custom domains do not resolve. The request falls through to canonical, which may 404 or show a generic page depending on the path.

---

## Custom Domain Context

### What Gets Loaded

```
CustomDomain
  ├─ Organization (via organization_id)
  │   └─ Plan (via plan_id)
  └─ Branding config (brand_name, logo_url, primary_color, custom_css)
```

All of this is available for the request lifecycle without additional lookups.

### Mode Availability

Determined by CustomDomain settings and Plan entitlements:

| Mode | Condition |
|------|-----------|
| Recipient | Always available |
| Sender | `public_homepage = true` OR `anonymous_create = true` OR authenticated |
| Member | Authenticated AND plan has `member_auth_on_custom_domain` |
| Admin | Authenticated AND plan has `admin_on_custom_domain` AND role is admin/owner |

### Routing Scope

All routes served are scoped to this organization. There is no org switcher. The organization context is implicit and unchangeable for the duration of the session.

### Authentication

Native login form on custom domain—not a redirect to canonical. The Session created has:
- `context_type = custom_domain`
- `custom_domain_id` = this domain
- `active_organization_id` = this domain's org

Sessions are domain-scoped. A session created on `secrets.clientco.com` is not valid on `onetimesecret.com` or `secrets.otherclient.com`.

### Domain-Scoped Members

If `membership.domain_scope_id` matches this domain, the account:
- Can authenticate on this domain
- Cannot access canonical domain workspace
- This domain is their entire OTS experience

If `membership.domain_scope_id` is null, the account:
- Can authenticate on this domain (as a platform user visiting)
- Can also access canonical domain
- Sees this as one of their org's custom domains

### Branding

All pages render with CustomDomain branding config:
- `brand_name` replaces "OneTimeSecret" in UI
- `logo_url` replaces OTS logo
- `primary_color` affects buttons, links, accents
- `custom_css` injected (Enterprise only, with CSP considerations)

---

## Canonical Context

### What Gets Loaded

For unauthenticated requests: nothing special, just the default OTS context.

For authenticated requests:
```
Session
  └─ Account
      └─ Memberships (all)
          └─ Organizations (all)
              └─ Plans (all)
```

Active organization determined by `session.active_organization_id`.

### Mode Availability

| Mode | Condition |
|------|-----------|
| Recipient | Always available |
| Sender | Always available |
| Member | Authenticated |
| Admin | Authenticated AND role is admin/owner in active org |

### Multi-Org Support

Authenticated accounts may belong to multiple organizations. The session tracks which org is currently active via `active_organization_id`. This affects:
- Which entitlements apply to secret creation
- Which custom domains appear in the dropdown
- Which activity log is shown
- Which team directory is shown

### Org Switcher

UI element for accounts with multiple memberships. Switching orgs:
1. Updates `session.active_organization_id`
2. Clears `session.active_custom_domain_id` (or sets to first domain in new org)
3. Does not invalidate session
4. Redirects to workspace root

### Custom Domain Selection (Canonical)

When creating a secret in canonical context, authenticated users can select which custom domain (if any) the secret should be associated with. This affects:
- Branding on the reveal page
- The domain in the shareable link

Stored in `session.active_custom_domain_id`. Options:
- None (canonical branding, canonical URL)
- Any verified custom domain owned by active organization

---

## Request Flow

### Anonymous Request to Custom Domain

```
GET https://secrets.clientco.com/

1. Domain detection: finds CustomDomain record
2. Load CustomDomain + Organization + Plan
3. Check mode availability:
   - public_homepage = true? Show create form
   - public_homepage = false? Show splash page
4. Render with tenant branding
```

### Authenticated Request to Custom Domain

```
GET https://secrets.clientco.com/dashboard

1. Domain detection: finds CustomDomain record
2. Load CustomDomain + Organization + Plan
3. Check session cookie (domain-scoped)
4. Validate session:
   - session.custom_domain_id matches current domain?
   - session not expired?
5. Load Account via session
6. Check membership:
   - Account has membership in this org?
   - If domain_scope_id set, does it match?
7. Check mode availability:
   - Plan has member_auth_on_custom_domain? Allow dashboard
   - No? Redirect to homepage or 403
8. Render workspace with tenant branding
```

### Anonymous Request to Canonical

```
GET https://onetimesecret.com/

1. Domain detection: no CustomDomain match
2. Canonical context, no session
3. Full sender mode available
4. Render with OTS branding
```

### Authenticated Request to Canonical

```
GET https://onetimesecret.com/dashboard

1. Domain detection: no CustomDomain match
2. Canonical context
3. Check session cookie
4. Validate session (context_type = canonical)
5. Load Account + all Memberships + all Organizations
6. Determine active org from session.active_organization_id
7. Full mode availability based on role in active org
8. Render with OTS branding, org context in header
```

---

## Secret Reveal Routing

Secret reveal is mode-independent and context-aware:

```
GET https://secrets.clientco.com/secret/abc123

1. Domain detection: custom domain context
2. Load Secret where key = 'abc123'
3. Verify secret.custom_domain_id matches current domain
   - If mismatch: the link was created for a different domain
   - Decide: 404, redirect to correct domain, or show anyway?
4. Render reveal page with tenant branding
```

```
GET https://onetimesecret.com/secret/xyz789

1. Domain detection: canonical context
2. Load Secret where key = 'xyz789'
3. Check secret.custom_domain_id:
   - If null: render with OTS branding
   - If set: render with that domain's branding (even though we're on canonical)
4. Render reveal page
```

### Cross-Domain Secret Access

A secret created on `secrets.clientco.com` has `custom_domain_id` pointing to that domain. If someone accesses it via the canonical domain:

**Option A: Strict domain enforcement**
- 404 or redirect to the correct domain
- Pro: Link origin is preserved
- Con: Adds redirects, potential for broken links if domain removed

**Option B: Brand-aware rendering**
- Render on canonical but with the custom domain's branding
- Pro: Links always work
- Con: Domain in URL doesn't match brand

**Option C: Canonical-only for canonical links**
- Secrets created on canonical only accessible on canonical
- Secrets created on custom domain only accessible on that domain
- Pro: Clean separation
- Con: Inflexible

Recommendation: Option B for reveal, Option A for other routes. The reveal page is recipient-facing and should just work. Other routes (dashboard, etc.) should enforce context.

---

## Session Boundaries

### Cookie Scoping

Sessions use domain-scoped cookies:
- Canonical session: cookie on `onetimesecret.com`
- Custom domain session: cookie on `secrets.clientco.com`

These are separate sessions. An account can be logged in to canonical and multiple custom domains simultaneously with separate sessions.

### Session Creation

On successful authentication:

```
create Session:
  account_id: authenticated account
  context_type: 'canonical' | 'custom_domain'
  custom_domain_id: current custom domain (or null)
  active_organization_id: 
    - custom domain: that domain's org
    - canonical: account's default org (or most recently active)
  active_custom_domain_id: null (canonical) | current domain (custom)
```

### Session Validation

Every authenticated request:

1. Cookie present and not expired?
2. Session record exists and not expired?
3. Context type matches current context?
4. For custom domain: `session.custom_domain_id` matches current domain?
5. Account still has valid membership in active org?

Failure at any step: clear session, redirect to login.

---

## API Context

API requests use header-based context rather than domain detection:

```
Authorization: Bearer <token>
X-OTS-Domain: secrets.clientco.com  (optional)
```

**Without `X-OTS-Domain`:**
- Canonical context
- Token's account and their active org setting
- Secrets created with canonical branding

**With `X-OTS-Domain`:**
- Custom domain context (if domain exists and token has access)
- Entitlements from that domain's org
- Secrets created with that domain's branding

Token scope must permit the requested domain. See `05-api.md` for token scoping rules.
