# Session App

## Overview

The Session App handles authentication boundary crossing. Login, logout, MFA, password reset, token refresh. It's a standalone module that cares about credentials and tokens, not secrets or dashboards. Minimal layout—neither marketing nor dashboard chrome.

---

## Design Principles

### Standalone Module

The Session App is intentionally isolated. It:
- Has its own minimal layout (not marketing, not dashboard)
- Doesn't import Secret App or Workspace App components
- Cares only about identity verification
- Hands off to other apps after authentication

### Domain Awareness

Session App operates on both canonical and custom domains:
- Same flows, different branding
- Sessions are domain-scoped
- No cross-domain session sharing

### Security First

- All forms protected against CSRF
- Rate limiting on authentication attempts
- No information leakage (email enumeration, etc.)
- Secure session management

---

## Routes

### Authentication

```
GET  /login                 # Login form
POST /login                 # Process login
GET  /logout                # Logout (could be POST for security)
POST /logout                # Process logout
```

### Registration (Canonical Only)

```
GET  /signup                # Registration form
POST /signup                # Process registration
GET  /verify-email/:token   # Email verification
```

### Password Reset

```
GET  /forgot-password       # Request reset form
POST /forgot-password       # Send reset email
GET  /reset-password/:token # Reset form
POST /reset-password/:token # Process reset
```

### MFA

```
GET  /mfa                   # MFA challenge form (during login)
POST /mfa                   # Verify MFA code
GET  /mfa/recovery          # Recovery code form
POST /mfa/recovery          # Verify recovery code
```

### Token Management (API)

```
POST /oauth/token           # Token endpoint (various grants)
POST /oauth/revoke          # Revoke token
```

---

## Login Flow

### Standard Login

```
GET /login
```

Display:
- Email field
- Password field
- "Forgot password?" link
- "Sign up" link (canonical only)
- Remember me checkbox (optional)

Branding:
- Canonical: OTS branding
- Custom domain: Tenant branding

```
POST /login
Content-Type: application/x-www-form-urlencoded

email=user@example.com&password=secret&remember_me=1
```

### Processing

1. **Find account** by email (case-insensitive)
   - Not found: generic error (no enumeration)

2. **Verify password**
   - Incorrect: generic error, increment failure counter
   - Rate limit: temp lockout after N failures

3. **Check MFA status**
   - TOTP enabled: redirect to /mfa
   - Not enabled: proceed

4. **Check context permissions**
   - Custom domain: does account have membership in this domain's org?
   - Domain-scoped: does membership.domain_scope_id match?

5. **Create session** (see Session Creation below)

6. **Set cookie** (domain-scoped)

7. **Redirect** to dashboard or return_to URL

### Error Handling

Generic error: "Invalid email or password"

Never reveal:
- Whether email exists
- Whether password is wrong
- Whether account is locked

Rate limiting message: "Too many attempts. Please try again in X minutes."

---

## MFA Challenge

After successful password verification, if TOTP is enabled:

```
GET /mfa
```

Display:
- TOTP code field (6 digits)
- "Use recovery code" link
- Session indicator (email, partially masked)

```
POST /mfa
Content-Type: application/x-www-form-urlencoded

code=123456
```

### Processing

1. **Verify pending auth state** (from previous step, stored securely)
2. **Validate TOTP code** against account.totp_secret
3. **Success**: complete session creation, redirect
4. **Failure**: increment counter, show error

### Recovery Codes

```
GET /mfa/recovery
```

Display:
- Recovery code field
- "Back to TOTP" link

```
POST /mfa/recovery
Content-Type: application/x-www-form-urlencoded

code=abcd-1234-efgh-5678
```

Processing:
- Validate against stored recovery codes
- If valid: mark code as used, complete login
- If invalid: error, don't reveal which codes exist

---

## Registration (Canonical Only)

Registration creates a new Account with an implicit personal Organization.

```
GET /signup
```

Display:
- Email field
- Password field (with strength indicator)
- Confirm password field
- Terms acceptance checkbox
- "Already have an account?" link

Custom domains do NOT show registration. Tenant users are:
- Invited by org admin
- Provisioned via SSO/SCIM
- Never self-register

```
POST /signup
Content-Type: application/x-www-form-urlencoded

email=user@example.com&password=secret&password_confirm=secret&terms=1
```

### Processing

1. **Validate email** format
2. **Check uniqueness** (no existing account)
3. **Validate password** strength
4. **Create Account**
   - email_verified_at = null
   - password_hash = hash(password)
5. **Create personal Organization**
   - name = "{email}'s Workspace"
   - personal = true
   - plan = Free
6. **Create Membership**
   - role = owner
   - domain_scope_id = null
7. **Send verification email**
8. **Show confirmation** (check your email)

### Email Verification

```
GET /verify-email/:token
```

Processing:
1. Find account by verification token
2. Set email_verified_at = now
3. Clear token
4. Redirect to login (or auto-login)

Token expiry: 24-48 hours. Resend option on login if unverified.

---

## Password Reset

### Request Reset

```
GET /forgot-password
```

Display:
- Email field
- "Back to login" link

```
POST /forgot-password
Content-Type: application/x-www-form-urlencoded

email=user@example.com
```

Processing:
1. Find account by email
2. If found: generate reset token, send email
3. If not found: still show success (no enumeration)
4. Always show: "If an account exists, we've sent reset instructions"

Token: secure random, stored hashed, expires in 1 hour.

### Reset Password

```
GET /reset-password/:token
```

Display:
- New password field
- Confirm password field
- Token validation (if invalid/expired, show error)

```
POST /reset-password/:token
Content-Type: application/x-www-form-urlencoded

password=newsecret&password_confirm=newsecret
```

Processing:
1. Validate token (exists, not expired, not used)
2. Validate password strength
3. Update account password_hash
4. Invalidate token
5. Invalidate all sessions (force re-login)
6. Redirect to login with success message

---

## Logout

```
GET /logout  (or POST for security)
```

Processing:
1. Find current session from cookie
2. Delete session record
3. Clear session cookie
4. Redirect to login (or homepage)

"Logout everywhere" option in settings:
- Delete all sessions for this account
- User must re-authenticate on all devices

---

## Session Management

### Session Creation

On successful authentication:

```
Session:
  id: random UUID
  account_id: authenticated account
  context_type: 'canonical' | 'custom_domain'
  custom_domain_id: current domain (or null for canonical)
  active_organization_id: determined below
  active_custom_domain_id: null (or same as custom_domain_id)
  ip_address: request IP
  user_agent: request User-Agent
  created_at: now
  expires_at: now + session_duration
```

**Determining active_organization_id:**

On canonical domain:
- If account has one org: that org
- If account has multiple: most recently active, or primary

On custom domain:
- The domain's organization (only option)

### Session Cookie

```
Set-Cookie: ots_session={session_id}; 
  Domain={current_domain};
  Path=/;
  HttpOnly;
  Secure;
  SameSite=Lax;
  Expires={session_expires_at or session cookie}
```

- `HttpOnly`: Not accessible to JavaScript
- `Secure`: HTTPS only
- `SameSite=Lax`: CSRF protection
- Domain-scoped: canonical cookie only valid on canonical

### Session Validation

On every authenticated request:

1. Cookie present?
2. Session record exists?
3. Session not expired?
4. Context matches? (canonical session on canonical, custom domain session on that domain)
5. For custom domain: account still has valid membership?

Failure: clear cookie, redirect to login.

### Session Refresh

Sessions can be extended on activity:
- Sliding expiration: reset expires_at on each request
- Fixed expiration: expires at set time regardless of activity

Configuration per deployment. Sliding is friendlier, fixed is more secure.

### Session Termination

Sessions end when:
- User logs out
- Session expires
- User changes password
- Admin revokes session
- Account membership revoked (for custom domain sessions)

---

## SSO Integration (Enterprise)

Enterprise orgs can use SAML or OIDC for authentication.

### SAML Flow

```
GET /login (on custom domain with SSO configured)
```

Display:
- "Login with {IdP Name}" button
- Optional: email/password form for non-SSO users

```
GET /saml/login
```

Processing:
1. Generate SAML AuthnRequest
2. Redirect to IdP SSO URL

```
POST /saml/callback
```

Processing:
1. Validate SAML Response signature
2. Extract attributes (email, name, groups)
3. Find or create Account
4. Find or create Membership (JIT provisioning)
5. Apply group → domain_scope mapping
6. Create session
7. Redirect to dashboard

### OIDC Flow

```
GET /oauth/authorize (if using OIDC)
```

Processing:
1. Redirect to IdP authorization endpoint
2. Include client_id, redirect_uri, scopes

```
GET /oauth/callback
```

Processing:
1. Exchange code for tokens
2. Validate ID token
3. Extract claims (email, name, groups)
4. Find or create Account
5. Find or create Membership
6. Create session
7. Redirect to dashboard

### Domain-Scoped SSO Users

When SSO user authenticates on custom domain:
- Their membership may be auto-scoped to that domain
- Based on SSO group mapping or org default
- They may never see canonical domain

---

## Invitation Flow

For invited users (non-SSO):

### Invite Created (by admin)

```
PendingInvite:
  id
  email
  organization_id
  role
  domain_scope_id (optional)
  invited_by_account_id
  token
  expires_at
```

Email sent with invite link.

### Invite Accepted

```
GET /invite/:token
```

Display:
- Organization name
- Invited by
- If account exists: "Login to accept"
- If no account: Registration form

```
POST /invite/:token
```

Processing:
1. Validate token
2. If no account: create Account (set email_verified_at = now)
3. Create Membership with invited role and domain_scope
4. Delete PendingInvite
5. Create session
6. Redirect to dashboard

---

## API Token Endpoint

For API authentication (separate from session auth):

```
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id=xxx&client_secret=yyy
```

Or for token exchange:

```
grant_type=urn:ietf:params:oauth:grant-type:token-exchange&
subject_token=xxx&
subject_token_type=urn:ietf:params:oauth:token-type:access_token
```

See `05-api.md` for full token model.

---

## Layout & Branding

### Minimal Layout

Session App pages use a minimal layout:
- Centered card
- Logo at top
- No navigation
- No marketing content
- No dashboard chrome

### Canonical Branding

- OTS logo
- OTS colors
- Links to marketing site (signup, about)

### Custom Domain Branding

- Tenant logo (from CustomDomain.logo_url)
- Tenant colors (from CustomDomain.primary_color)
- No "Sign up" link (registration is canonical only)
- May include "Powered by OTS" footer (or not, Enterprise choice)

---

## Security Measures

### Rate Limiting

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /login | 5 attempts | per account per 15 min |
| POST /login | 20 attempts | per IP per hour |
| POST /forgot-password | 3 requests | per email per hour |
| POST /signup | 5 registrations | per IP per hour |
| POST /mfa | 5 attempts | per pending session |

### Lockout

After rate limit exceeded:
- Account lockout: temporary (15-60 min)
- IP lockout: temporary (1 hour)
- Show generic message, don't reveal lockout reason

### Audit Logging

All authentication events logged:
- Login success/failure
- MFA success/failure
- Password reset request
- Session creation/termination
- SSO events

Include: timestamp, IP, user agent, outcome.

### CSRF Protection

All POST forms include CSRF token:
- Token generated per session
- Validated on submission
- Failure: 403

### Secure Cookies

All session cookies:
- HttpOnly
- Secure (HTTPS only)
- SameSite=Lax
- Domain-scoped

---

## Error Pages

### 401 Unauthorized

When authentication required but missing:
- Redirect to /login
- Preserve return_to URL

### 403 Forbidden

When authenticated but not authorized:
- "You don't have permission to access this resource"
- Link to dashboard

### Session Expired

When session cookie present but invalid:
- Clear cookie
- "Your session has expired. Please log in again."
- Redirect to login
