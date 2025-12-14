# Colonel App

## Overview

The Colonel App provides platform oversight and dangerous operations. Utilitarian UI, raw data views, safety rails on destructive actions. OTS operators only—never surfaces on custom domains, never accessible to customers.

---

## Access Control

### Who Has Access

- OTS platform operators
- Engineering team members with elevated privileges
- Not customers, not organization admins, not support staff

### Authentication

Separate from customer auth:
- Dedicated operator accounts (not regular Account records)
- Hardware key required (WebAuthn/FIDO2)
- IP allowlist
- Session timeout: 15 minutes inactivity

### Authorization

Role-based within operator team:
| Role | Capabilities |
|------|-------------|
| `viewer` | Read-only access to all data |
| `support` | View + limited write (unlock accounts, extend trials) |
| `operator` | Full operational capabilities |
| `superuser` | Everything including destructive operations |

---

## Routes

### Dashboard

```
GET /colonel                # Platform overview
```

### Accounts

```
GET  /colonel/accounts               # Search/list accounts
GET  /colonel/accounts/:id           # Account detail
POST /colonel/accounts/:id/unlock    # Clear login lockout
POST /colonel/accounts/:id/reset-mfa # Remove MFA (with verification)
POST /colonel/accounts/:id/verify    # Force email verification
POST /colonel/accounts/:id/impersonate # Begin impersonation session
```

### Organizations

```
GET  /colonel/organizations          # Search/list organizations
GET  /colonel/organizations/:id      # Organization detail
POST /colonel/organizations/:id/plan # Change plan (admin override)
POST /colonel/organizations/:id/extend-trial # Extend trial period
```

### Domains

```
GET  /colonel/domains                # All custom domains
GET  /colonel/domains/:id            # Domain detail
POST /colonel/domains/:id/verify     # Force verification
POST /colonel/domains/:id/suspend    # Suspend domain
POST /colonel/domains/:id/unsuspend  # Unsuspend domain
```

### Secrets

```
GET  /colonel/secrets                # Search secrets (metadata only)
GET  /colonel/secrets/:id            # Secret detail (metadata only)
POST /colonel/secrets/:id/extend     # Extend TTL
POST /colonel/secrets/:id/expire     # Force expiration
```

### System

```
GET  /colonel/system                 # System health
GET  /colonel/system/jobs            # Background job status
GET  /colonel/system/metrics         # Platform metrics
POST /colonel/system/maintenance     # Toggle maintenance mode
```

### Audit

```
GET /colonel/audit                   # Platform-wide audit log
GET /colonel/audit/operators         # Operator action log
```

---

## Platform Dashboard

### Key Metrics

**Volume:**
- Secrets created (today, 7d, 30d)
- Secrets revealed (today, 7d, 30d)
- Active accounts (DAU, WAU, MAU)
- Active organizations

**Health:**
- API response times (p50, p95, p99)
- Error rates
- Background job queue depth
- Storage utilization

**Business:**
- Organizations by plan tier
- MRR (monthly recurring revenue)
- Trial conversions
- Churn rate

### Alerts

Active alerts from monitoring:
- High error rate
- Elevated latency
- Queue backup
- Certificate expiry
- Storage warnings

---

## Account Operations

### Account Search

Search by:
- Email (partial match)
- Account ID
- Organization membership
- Domain scope
- Registration date range
- Status (active, locked, unverified)

### Account Detail View

```
Account: user@example.com
ID: acc_xxx
Created: 2024-01-15
Email Verified: Yes
MFA: TOTP enabled

Organizations:
- Acme Corp (owner) - Business plan
- Personal (owner) - Free plan

Sessions:
- Chrome/Mac, 192.168.1.1, active now
- Mobile/iOS, 10.0.0.1, 2 hours ago

Recent Activity:
- Secret created, 5 min ago
- Login, 2 hours ago
- Password changed, 3 days ago
```

### Account Actions

**Unlock Account**
- Clears login failure counter
- Removes temporary lockout
- Requires: support role
- Audit logged

**Reset MFA**
- Removes TOTP secret
- Invalidates recovery codes
- User must re-enroll on next login
- Requires: operator role
- Requires: verification (ticket number, identity proof)
- Audit logged

**Force Email Verification**
- Sets email_verified_at = now
- For cases where email delivery failed
- Requires: support role
- Audit logged

**Impersonate**
- Creates session as this account
- All actions logged as impersonation
- Banner visible throughout
- Time-limited (30 min max)
- Requires: operator role
- Requires: justification text
- Audit logged

---

## Organization Operations

### Organization Search

Search by:
- Name (partial match)
- Slug
- Organization ID
- Plan tier
- Custom domain hostname
- Owner email

### Organization Detail View

```
Organization: Acme Corp
ID: org_xxx
Slug: acme-corp
Created: 2024-01-15
Plan: Business (paid)
Billing: Current

Owner: ceo@acme.com
Members: 12

Custom Domains:
- secrets.acme.com (verified, active)
- secure.acme.io (pending verification)

Limits:
- Secrets/day: 847 / 1000
- Custom domains: 2 / 5
- Members: 12 / unlimited

Recent Activity:
- Secret created, 1 min ago
- Member invited, yesterday
- Domain added, last week
```

### Organization Actions

**Change Plan (Override)**
- Bypass billing, set plan directly
- For: partnerships, disputes, errors
- Requires: superuser role
- Requires: justification
- Audit logged

**Extend Trial**
- Add days to trial period
- For: sales process, technical issues
- Requires: support role
- Audit logged

---

## Domain Operations

### Domain List

All custom domains with:
- Hostname
- Organization
- Verification status
- Traffic (secrets created)
- Last activity

### Domain Detail View

```
Domain: secrets.acme.com
ID: dom_xxx
Organization: Acme Corp
Created: 2024-01-15
Verified: 2024-01-16
Status: Active

Branding:
- Brand name: Acme Secure Share
- Logo: https://...
- Color: #1E88E5

Settings:
- Public homepage: Yes
- Anonymous create: No
- Incoming secrets: security@acme.com

Stats (30d):
- Secrets created: 1,234
- Secrets revealed: 987
- Unique creators: 45
- Unique recipients: 890
```

### Domain Actions

**Force Verification**
- Set verified_at = now
- For: DNS propagation issues, manual verification
- Requires: operator role
- Audit logged

**Suspend Domain**
- Domain stops resolving to OTS
- Existing secrets: remain accessible via canonical
- For: abuse, non-payment, customer request
- Requires: operator role
- Requires: justification
- Customer notified
- Audit logged

**Unsuspend Domain**
- Restore normal operation
- Requires: operator role
- Audit logged

---

## Secret Operations

### Secret Search

Search by:
- Key (exact match only)
- Organization
- Custom domain
- Creator account
- Date range
- Status (pending, revealed, expired)

Note: Search by content is NOT possible (encrypted, and we don't want it).

### Secret Detail View

```
Secret: abc123xyz
ID: sec_xxx
Organization: Acme Corp
Domain: secrets.acme.com
Created: 2024-01-15 10:30:00
Creator: user@acme.com

Status: Pending (not yet revealed)
TTL: 3600 seconds
Expires: 2024-01-15 11:30:00
Passphrase: Yes

[Content is encrypted and not viewable]
```

### Secret Actions

**Extend TTL**
- Add time before expiration
- For: customer request, system issues
- Does not reveal content
- Requires: support role
- Audit logged

**Force Expiration**
- Set expires_at = now
- Secret becomes unretrievable
- For: abuse reports, customer request
- Requires: operator role
- Requires: justification
- Audit logged

**Note on Content Access**

Colonel CANNOT view secret content. By design:
- Content is encrypted at rest
- No admin backdoor
- Protects both customers and operators
- If content must be retrieved (legal), requires extraordinary process

---

## System Operations

### System Health

```
Status: Operational

Services:
- API: ✓ healthy (23ms avg)
- Web: ✓ healthy (45ms avg)
- Workers: ✓ healthy (3 jobs queued)
- Database: ✓ healthy (12ms avg)
- Cache: ✓ healthy (2ms avg)
- Storage: ✓ healthy (78% used)

Regions:
- us-east: ✓ operational
- eu-west: ✓ operational
- ap-south: ✓ operational
```

### Background Jobs

```
Queue Status:
- secret_cleanup: 0 pending, 12,345 processed today
- email_delivery: 3 pending, 567 processed today
- audit_export: 1 pending (in progress)
- webhook_delivery: 0 pending, 89 processed today

Failed Jobs (last 24h):
- email_delivery: 2 (retry scheduled)
- webhook_delivery: 1 (target unreachable)
```

### Maintenance Mode

Toggle platform-wide maintenance:
- API returns 503
- Web shows maintenance page
- Background jobs pause
- Custom domains show maintenance page

Requires: operator role
Announcement: optional message

---

## Audit Logs

### Platform Audit Log

All customer activity, searchable:
- Secret lifecycle events
- Authentication events
- Configuration changes
- Billing events

Filters:
- Organization
- Account
- Event type
- Date range
- IP address

### Operator Audit Log

All Colonel actions:
```
2024-01-15 10:30:00 | operator@ots.com | account.unlock | acc_xxx | "Customer locked out after password manager issue"
2024-01-15 10:25:00 | operator@ots.com | impersonate.start | acc_yyy | "Investigating billing display bug #1234"
2024-01-15 10:20:00 | support@ots.com | trial.extend | org_zzz | 14 days | "Sales process extended"
```

Retention: Indefinite (operator actions are never deleted)

---

## Safety Rails

### Confirmation Requirements

Destructive actions require:
1. Type confirmation phrase
2. Justification text
3. Elevated role

Example:
```
Force expire secret sec_xxx?

This action cannot be undone. The secret will be immediately 
unretrievable even if the recipient has the link.

Type "expire sec_xxx" to confirm: [____________]
Justification: [________________________]
Ticket reference: [____________]

[Cancel] [Force Expire]
```

### Two-Person Rule

Critical operations require approval from second operator:
- Mass operations (affecting >10 items)
- Plan downgrades (Business → Free)
- Account deletion
- Database operations

### Blast Radius Limits

Bulk operations capped:
- Max 100 items per operation
- Requires explicit enumeration (no wildcards)
- Progress shown, can abort mid-operation

### Impersonation Constraints

When impersonating:
- Cannot access Colonel
- Cannot change account password
- Cannot change MFA settings
- Cannot delete account
- Banner always visible
- Time limit enforced
- All actions attributed to operator

---

## Reporting

### Scheduled Reports

- Daily: Volume summary, error summary
- Weekly: Growth metrics, churn analysis
- Monthly: Business review, security summary

### Ad-hoc Reports

Generate reports on:
- Account creation by date
- Secrets by organization
- Domain usage
- Plan distribution
- Geographic distribution

Export: CSV, JSON

### Compliance Reports

For customer requests (GDPR, etc.):
- Account data export
- Activity history
- Data deletion verification

Requires: ticket, approval, audit logging

---

## UI Design

### Principles

- Utilitarian, not beautiful
- Information-dense
- Fast to navigate
- Clear action consequences
- Consistent patterns

### Layout

```
[OTS Colonel] [Dashboard] [Accounts] [Orgs] [Domains] [Secrets] [System] [Audit] | operator@ots.com [Logout]

+------------------------------------------------------------------+
| Search: [_________________________] [Type ▾] [Search]            |
+------------------------------------------------------------------+
| Results / Detail View                                            |
|                                                                  |
| ...                                                              |
+------------------------------------------------------------------+
| Actions                                                          |
| [Action 1] [Action 2] [Dangerous Action]                         |
+------------------------------------------------------------------+
```

### Color Coding

- Green: Healthy, active, verified
- Yellow: Warning, pending, approaching limit
- Red: Error, failed, suspended
- Gray: Inactive, expired, deleted

### Dangerous Actions

- Red button styling
- Separate section
- Confirmation required
- Clear consequence text
