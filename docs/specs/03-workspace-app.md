# Workspace App

## Overview

The Workspace App is the authenticated management interface. Activity feed, team directory, settings, billing. Always requires authentication. OTS-branded on canonical, tenant-branded for Enterprise domain-scoped users.

---

## Access Rules

### Canonical Domain

All authenticated accounts have workspace access. Features gated by:
- Plan entitlements
- Role (member, admin, owner)

### Custom Domain

Workspace access is plan-gated:

| Plan | Workspace on Custom Domain |
|------|---------------------------|
| Free | No |
| Pro | No |
| Business | Yes (member features) |
| Enterprise | Yes (member + admin features) |

If plan doesn't include `member_auth_on_custom_domain`, custom domain users see Secret App only.

---

## Routes

### Dashboard

```
GET /dashboard              # Overview: recent activity, quick stats, pending items
```

### Activity

```
GET /activity               # Full activity log with filters
GET /activity/:id           # Single activity detail (if needed)
```

### Team

```
GET /members                # Member directory
GET /members/:id            # Member profile (limited info)
POST /members/direct        # Send direct secret (member-to-member)
```

### Settings

```
GET /settings               # Personal settings overview
GET /settings/profile       # Display name, timezone, locale
GET /settings/security      # Password, 2FA
GET /settings/sessions      # Active sessions, revoke
```

### Admin (Role-gated)

```
GET /admin                  # Admin dashboard
GET /admin/settings         # Organization settings
GET /admin/domains          # Custom domain management
GET /admin/domains/:id      # Single domain config
GET /admin/members          # Member management
POST /admin/members/invite  # Send invite
DELETE /admin/members/:id   # Remove member
PATCH /admin/members/:id    # Change role
GET /admin/billing          # Billing (canonical only)
GET /admin/audit            # Audit log viewer
GET /admin/sso              # SSO config (Enterprise)
```

---

## Dashboard

The landing page for authenticated users. Quick overview of relevant state.

### Contents

**Quick Stats:**
- Secrets created (last 7/30 days)
- Pending secrets (created by me, not yet revealed)
- Team size (if relevant)

**Recent Activity:**
- Last 5-10 activity entries
- Link to full activity log

**Pending Items:**
- Secrets I created, awaiting reveal
- Direct secrets sent to me (Business+)
- Invitations pending acceptance (admin)

**Quick Actions:**
- Create secret
- Invite member (admin)
- View activity

### Context Awareness

On canonical domain with multiple orgs:
- Show active org name in header
- Org switcher accessible
- Stats scoped to active org

On custom domain:
- No org switcher (single org context)
- Tenant branding (Enterprise)

---

## Activity Log

Record of secret lifecycle events for this organization.

### Entry Types

| Action | Description | Visible To |
|--------|-------------|------------|
| `secret_created` | Secret created | Creator, Admin |
| `secret_revealed` | Secret viewed | Creator, Admin |
| `secret_expired` | Secret expired unviewed | Creator, Admin |
| `secret_burned` | Secret destroyed early | Creator, Admin |
| `direct_sent` | Direct secret sent | Sender, Recipient, Admin |
| `direct_revealed` | Direct secret viewed | Sender, Recipient, Admin |

### Entry Data

```
ActivityEntry (UI model, derived from AuditEntry)
  id
  action
  created_at
  metadata:
    ttl_seconds
    passphrase_used: boolean
    recipient_name (for direct)
    revealed_by_ip (for reveals, admin only)
```

### Filtering

- By action type
- By date range
- By creator (admin only)
- By status (pending, revealed, expired)

### Pagination

Standard cursor-based pagination. Default 25 per page.

### Privacy

- Secret content never shown
- IP addresses shown to admins only
- Passphrase existence shown, not value

---

## Team Directory

List of organization members. Used for:
- Finding people (name, email)
- Direct secret sending (Business+)

### Display

| Field | Visible To |
|-------|------------|
| Display name | All members |
| Email | All members |
| Role | All members |
| Joined date | All members |
| Domain scope | Admins only |
| Provisioned via | Admins only |

### Direct Secret Sending

Business+ feature. From team directory or as action:

1. Select recipient
2. Compose secret (same as normal create)
3. No link generated
4. Recipient notified
5. Appears in recipient's dashboard

---

## Personal Settings

Account-level settings. Available to all authenticated users.

### Profile

- Display name (shown in activity, team directory)
- Email (read-only here; change requires verification flow)
- Timezone (for activity timestamps)
- Locale (for UI language)

### Security

**Password:**
- Change password (requires current password)
- Set password (for SSO-only accounts adding password)

**Two-Factor Authentication:**
- Enable TOTP (setup with QR code)
- Disable TOTP (requires current code)
- View recovery codes
- Regenerate recovery codes

### Sessions

List of active sessions:
- Current session (marked)
- Other sessions (device, IP, last active)
- Revoke individual sessions
- Revoke all other sessions

---

## Admin: Organization Settings

Admin/owner access. Organization-level configuration.

### General

- Organization name
- Organization slug (URL identifier)
- Owner (transfer ownership)

### Plan & Limits

- Current plan (read-only, link to billing)
- Usage vs limits:
  - Secrets created / max per day
  - Custom domains / max domains
  - Members / max members

---

## Admin: Custom Domain Management

Admin/owner access. Manage organization's custom domains.

### Domain List

For each domain:
- Hostname
- Verification status
- Created date
- Quick stats (secrets created via this domain)

### Add Domain

1. Enter hostname
2. System generates verification token
3. Display DNS instructions:
   ```
   Add TXT record:
   Host: _onetimesecret.{hostname}
   Value: {verification_token}
   ```
4. "Verify" button polls DNS

### Domain Configuration

Once verified:

**Branding:**
- Brand name (replaces "OneTimeSecret")
- Logo URL
- Primary color (hex)
- Favicon URL
- Custom CSS (Enterprise only)

**Mode Settings:**
- Public homepage (checkbox)
- Anonymous create (checkbox)
- Incoming secrets email (text field)

**Member Settings (Business+):**
- Allow member authentication (plan-gated)
- Default role for SSO users

### Remove Domain

- Confirmation required
- Existing secrets with this domain_id: decide fate
  - Option A: Secrets remain, render with canonical branding
  - Option B: Secrets deleted (harsh)
  - Recommendation: Option A with warning

---

## Admin: Member Management

Admin/owner access. Manage organization membership.

### Member List

For each member:
- Account (name, email)
- Role (owner, admin, member)
- Domain scope (if set)
- Provisioned via (invite, sso, scim)
- Joined date
- Last active (optional)

### Invite Member

1. Enter email
2. Select role (member or admin; owner can invite admins)
3. Select domain scope (optional, Enterprise)
4. Send invitation

Invitation:
- Creates pending invite record
- Sends email with invite link
- Link expires after X days
- Accepting creates Account (if needed) and Membership

### Change Role

Admin can change members to admin or member.
Owner can change anyone's role.
Cannot demote the owner (must transfer ownership first).

### Domain Scope Assignment (Enterprise)

For Enterprise orgs, admin can:
- Assign member to a domain scope
- Remove domain scope (promote to platform user)

Domain-scoped members:
- Can only access that custom domain
- Cannot see canonical domain workspace
- Typically SSO/SCIM provisioned

### Remove Member

- Confirmation required
- Membership deleted
- Account remains (may belong to other orgs)
- Activity log entries: remain, attributed to "[removed member]"
- Pending secrets created by them: remain until revealed/expired

---

## Admin: Billing

**Canonical domain only.** Billing is always managed through OTS, not custom domains.

### Display

- Current plan
- Plan features/limits
- Billing cycle
- Payment method (masked)
- Invoice history

### Actions

- Upgrade plan
- Downgrade plan (effective at cycle end)
- Update payment method
- Download invoices
- Cancel subscription

### Plan Changes

Upgrade: immediate, prorated.
Downgrade: scheduled for cycle end.
Cancel: scheduled for cycle end, then convert to Free.

On downgrade/cancel, if over new limits:
- Custom domains: excess become "grandfathered" (work but can't add more)
- Members: excess remain but can't add more
- Features: disabled at cycle end

---

## Admin: Audit Log

Plan-gated (Pro+). Comprehensive log of organization activity.

### Entry Types

Includes activity log entries plus:
- `member_invited`
- `member_joined`
- `member_removed`
- `member_role_changed`
- `domain_added`
- `domain_verified`
- `domain_configured`
- `domain_removed`
- `settings_changed`
- `plan_changed`

### Entry Data

More detail than activity log:
- Full metadata
- IP addresses
- Affected entities

### Export

- CSV download
- Date range filter
- JSON export (for SIEM integration)

### Retention

Based on plan:
- Pro: 90 days
- Business: 1 year
- Enterprise: 2 years or custom

---

## Admin: SSO Configuration

Enterprise only. Configure identity provider integration.

### SAML Setup

- Entity ID
- SSO URL
- Certificate
- Attribute mapping:
  - Email (required)
  - Display name (optional)
  - Groups (for role assignment)

### OIDC Setup

- Client ID
- Client Secret
- Discovery URL (or manual endpoints)
- Scopes
- Attribute mapping

### Provisioning Options

- Just-in-time provisioning (create account on first login)
- SCIM endpoint URL (for directory sync)
- Default role for new users
- Default domain scope for new users

### Domain Scope Mapping

Map SSO groups to domain scopes:
- Group "sales" → domain scope `secrets.sales.clientco.com`
- Group "engineering" → no domain scope (platform access)

---

## Branding

### Canonical Domain

Always OTS branding:
- OTS logo
- OTS colors
- OTS name

### Custom Domain (Business)

Secret App: Tenant branding
Workspace App: OTS branding with tenant context (org name shown)

### Custom Domain (Enterprise)

Secret App: Tenant branding
Workspace App: Tenant branding (full white-label)

Enterprise workspace includes:
- Tenant logo
- Tenant colors
- Tenant name
- Minimal OTS attribution (footer link or none)

---

## Navigation

### Canonical

```
[OTS Logo] [Dashboard] [Activity] [Team] [Settings] [Admin ▾] [Org: Acme ▾] [User ▾]
```

Admin dropdown (if admin/owner):
- Settings
- Domains
- Members
- Billing
- Audit

Org dropdown (if multiple):
- List of orgs
- Switch org

### Custom Domain (Business)

```
[OTS Logo] [Dashboard] [Activity] [Team] [Settings] [User ▾]
```

No admin access on custom domain at Business tier.
No org switcher (single org context).

### Custom Domain (Enterprise)

```
[Tenant Logo] [Dashboard] [Activity] [Team] [Settings] [Admin ▾] [User ▾]
```

Admin dropdown includes domain-appropriate settings (no billing).
Full tenant branding.
