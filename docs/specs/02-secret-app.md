# Secret App

## Overview

The Secret App handles the core transit operation: create, share, reveal, destroy. This is the only part of the platform that gets white-labeled. It's the high-traffic path and must be lightweight and fast.

---

## The Transit Lifecycle

```
Create → Share Link → Recipient Opens → Gone
```

There is no "view my secrets" because revealed secrets don't exist. There is no "edit secret" because secrets are immutable. The lifecycle is unidirectional and terminal.

---

## Routes

### Create Flow

```
GET  /                     # Homepage with create form (if enabled)
POST /secrets              # Create secret
GET  /secrets/:key/created # Confirmation with shareable link
```

### Reveal Flow

```
GET  /secret/:key          # Reveal page (shows metadata, passphrase prompt if needed)
POST /secret/:key/reveal   # Perform reveal (returns content, destroys secret)
```

### Burn Flow (Optional)

```
POST /secret/:key/burn     # Destroy without revealing (creator only, requires auth)
```

---

## Create Form

### Fields

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `value` | text | yes | max size from plan.max_secret_size_bytes |
| `ttl` | select | yes | options from plan.max_ttl_seconds |
| `passphrase` | text | no | if provided, recipient must enter it |

### TTL Options

Presented as human-readable durations, mapped to seconds:
- 5 minutes (300)
- 30 minutes (1800)
- 1 hour (3600)
- 4 hours (14400)
- 12 hours (43200)
- 1 day (86400)
- 3 days (259200)
- 7 days (604800)
- 14 days (1209600)
- 30 days (2592000)

Options filtered by `plan.max_ttl_seconds`. Free tier might cap at 7 days.

### Authentication State

**Anonymous creator:**
- `created_by_account_id` = null
- No activity log entry (nothing to attach it to)
- No burn capability

**Authenticated creator:**
- `created_by_account_id` = session.account_id
- Activity log entry created
- Burn link shown on confirmation page (if secret still exists)
- Secret visible in "pending" section of dashboard until revealed/expired

### Context Attribution

When creating a secret:
- `organization_id` = session.active_organization_id (for entitlement tracking)
- `custom_domain_id` = 
  - In custom domain context: current domain
  - In canonical context: session.active_custom_domain_id (may be null)

---

## Create Processing

### Request Handling

```
POST /secrets
Content-Type: application/x-www-form-urlencoded

value=the+secret+content&ttl=3600&passphrase=optional
```

### Processing Steps

1. **Validate input**
   - Value present and non-empty
   - TTL within allowed range for plan
   - Size within plan.max_secret_size_bytes

2. **Check rate limits**
   - plan.max_secrets_per_day (if set)
   - Global rate limiting (IP-based for anonymous)

3. **Generate key**
   - URL-safe random string
   - Sufficient entropy (e.g., 22 chars base62 = ~131 bits)
   - Verify uniqueness (collision extremely unlikely but check)

4. **Encrypt value**
   - Encryption at rest (server-side key)
   - If passphrase provided: additional layer with passphrase-derived key
   - Store encryption_version for future algorithm changes

5. **Create Secret record**
   - Set expires_at = now + ttl_seconds
   - Set passphrase_required = (passphrase provided?)
   - Set context fields (organization_id, custom_domain_id, created_by_account_id)

6. **Create audit entry** (if plan.audit_log and authenticated)

7. **Redirect to confirmation**

### Response

```
HTTP/1.1 303 See Other
Location: /secrets/{key}/created
```

---

## Confirmation Page

Shows after successful creation. Displays:

- **Shareable link**: Full URL to reveal page
- **Expiration**: Human-readable time until expiry
- **Passphrase reminder**: If set, remind creator (they won't see it again)
- **Burn link**: If authenticated, option to destroy early (goes to POST /secret/:key/burn)

### Link Format

```
https://{domain}/secret/{key}
```

Domain is:
- Custom domain if `secret.custom_domain_id` is set
- Canonical domain otherwise

The confirmation page should make copying the link easy (copy button, QR code optional).

### No Secret Display

The confirmation page does NOT show the secret content. The creator entered it; they know what it is. Showing it again is a security risk (shoulder surfing, screen sharing).

---

## Reveal Page

### Initial Load (GET /secret/:key)

Fetch secret by key. Possible states:

**Secret not found (404):**
- Key doesn't match any record
- Display: "This secret doesn't exist or has already been viewed"
- No distinction between "never existed" and "already revealed" (security)

**Secret expired (410):**
- Found but `expires_at` < now
- Display: "This secret has expired"
- Trigger cleanup (or rely on background job)

**Secret exists, passphrase required:**
- Display passphrase entry form
- Form POSTs to same URL with passphrase

**Secret exists, no passphrase:**
- Display reveal button
- "This secret can only be viewed once. Ready?"

### Branding

Reveal page renders with branding from `secret.custom_domain_id`:
- If set: that domain's brand_name, logo_url, colors
- If null: OTS branding

This is true regardless of which domain the reveal page is accessed from (see routing document for cross-domain access policy).

---

## Reveal Processing

### Request Handling

```
POST /secret/:key/reveal
Content-Type: application/x-www-form-urlencoded

passphrase=optional
```

### Processing Steps

1. **Fetch secret** by key (with row lock if supported)

2. **Validate state**
   - Exists? If not: 404
   - Already revealed? If yes: 410 (or 404 for security)
   - Expired? If yes: 410

3. **Validate passphrase** (if required)
   - Derive key from passphrase
   - Attempt decryption
   - If fails: re-render reveal page with error

4. **Decrypt value**
   - Remove passphrase layer (if any)
   - Remove server-side encryption layer

5. **Mark revealed**
   - Set `revealed_at` = now
   - Set `revealed_by_ip` = request IP
   - Update record (or delete immediately, see cleanup)

6. **Create audit entry** (if plan.audit_log)

7. **Return decrypted value**

### Response

```
HTTP/1.1 200 OK
Content-Type: text/html

<!-- Rendered page showing decrypted secret -->
```

The decrypted value is displayed in a read-only text area. Options:
- Copy to clipboard button
- Download as text file (optional)
- Clear display after viewing (optional timer)

### Post-Reveal Display

After showing the secret:
- Clear indication that it's destroyed ("This secret has been permanently deleted")
- No "view again" option
- No save/cache (appropriate headers)

---

## Burn (Early Destruction)

### Authorization

Only available to authenticated creators. The request must include:
- Valid session
- `session.account_id` matches `secret.created_by_account_id`

### Request

```
POST /secret/:key/burn
```

No body needed. Session cookie provides auth.

### Processing

1. Validate session
2. Fetch secret by key
3. Verify ownership (created_by_account_id matches)
4. Verify not already revealed
5. Delete secret
6. Create audit entry
7. Redirect to confirmation

### Response

```
HTTP/1.1 303 See Other
Location: /secrets/{key}/burned
```

Burned confirmation page shows:
- "Secret destroyed"
- "The link will no longer work"

---

## Member-to-Member Sharing

Business+ feature. Variation on create flow where secret is sent directly to an organization member.

### Create Form (Direct)

Additional field:
- `recipient` - select from organization member directory

When recipient is selected:
- `key` = null (no URL generated)
- `recipient_account_id` = selected member
- Notification sent to recipient

### Notification

Recipient receives:
- Email notification (if enabled)
- In-app notification (dashboard indicator)
- No link in notification—they must log in

### Recipient Reveal

Recipient logs in, sees pending secret in dashboard. Reveal flow is similar but:
- No URL/key involved
- Authorization: session.account_id must match secret.recipient_account_id
- Accessed via dashboard, not direct link

---

## Incoming Secrets

Business+ feature. External parties send secrets to an organization via custom domain.

### Configuration

On CustomDomain:
- `incoming_secrets_email` = delivery destination

### Create Form (Incoming)

Simplified form for external visitors:
- Secret value
- Optional: sender name/email (not required, stored in metadata)
- TTL (may be fixed or limited options)

### Processing

1. Create secret normally
2. Generate key and link
3. Send email to `incoming_secrets_email` containing link
4. Show confirmation to sender: "Your secure message has been sent"

The organization receives the link and reveals it like any other secret.

---

## Cleanup

### Revealed Secrets

Options:
- **Immediate deletion**: Delete record in same transaction as reveal
- **Marked + batch delete**: Set revealed_at, background job deletes later

Immediate deletion is cleaner but batch deletion allows for:
- Audit log correlation (if log is separate from secret)
- Brief grace period for support issues

### Expired Secrets

Background job runs continuously:
- `DELETE FROM secrets WHERE expires_at < now()`
- Or: `DELETE FROM secrets WHERE revealed_at IS NOT NULL AND revealed_at < now() - interval '1 hour'`

### No Soft Deletes

When a secret is gone, it's gone. No `deleted_at` column. No archive. The data is unrecoverable by design.

---

## Security Considerations

### Enumeration Protection

- Keys are high-entropy random strings
- No sequential IDs exposed
- Rate limiting on reveal attempts
- Same response for "not found" and "already revealed"

### Passphrase Handling

- Passphrase never stored in plaintext
- Used to derive encryption key (Argon2, PBKDF2, etc.)
- Limited attempts before lockout (3-5)
- Lockout is per-secret, temporary

### Content Security

- Decrypted content displayed, not downloadable by default
- `Cache-Control: no-store` on reveal pages
- CSP prevents content injection
- No client-side storage of decrypted content

### Logging

Audit log (when enabled) records:
- Creation: who, when, org, ttl, passphrase (yes/no, not value)
- Reveal: when, IP, success/failure
- Burn: who, when

Never logged:
- Secret content (encrypted or decrypted)
- Passphrase

---

## White-Labeling

The Secret App is the only part that gets fully white-labeled. On custom domains:

### Replaced

- Logo → custom domain logo
- Brand name → custom domain brand_name
- Primary color → custom domain primary_color
- Favicon → custom domain favicon (if provided)

### Retained (by default)

- Core functionality
- Security messaging
- Error pages

### Custom CSS (Enterprise)

Enterprise plans can inject custom CSS for deeper branding. This is loaded with appropriate CSP restrictions.

---

## Performance Requirements

The Secret App is the high-traffic path. Requirements:

- **Create**: < 200ms p99
- **Reveal page load**: < 100ms p99
- **Reveal processing**: < 300ms p99 (includes decryption)

Caching:
- Static assets cached aggressively
- Secret content never cached
- Branding config cached per-domain (invalidate on update)

Database:
- Secrets table indexed on key (unique, fast lookup)
- No joins needed for reveal flow
- Consider read replicas for high-traffic custom domains
