# Renta UG · Development & Security Checklist (250 items)

Audit date: 23 Nov 2026. Scope: this codebase (Vue app, Netlify Functions, Express server, Supabase SQL).
Hosting: Netlify (site + functions) and Supabase (Postgres, Auth, Realtime).

**Status key**

| Status | Meaning |
| --- | --- |
| ✅ | Implemented and verified (checked in the code during this audit, or tested) |
| 🟡 | Implemented but not tested, or only partly in place (the note says which) |
| ❌ | Not implemented |
| ➖ | Not applicable to this app (the note says why) |

**Fixed in this audit:** first sign-in account takeover (setup codes), phone sign-in password guessing
(lockout), landlords linking other people's accounts (`tenants.user_id` guard), main admin password in the
repo, no security headers / CSP, 4 high-severity dependency vulnerabilities, weak sign-up passwords,
automated tests in the deploy. See "Actions for the owner" at the end for what can't be done in code.

---

## 1. The 12 quick attacks

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 1 | Script username | ✅ | No `v-html` / `innerHTML` anywhere; Vue escapes all text, emails escape with `esc()`. CSP now blocks inline scripts too. |
| 2 | Change the ID in the URL | ✅ | Row Level Security on all 21 tables: another landlord's tenant / payment ID returns nothing. |
| 3 | Type `/admin` | ✅ | Admin UI is `/admin2026`, router requires role `superadmin`; every admin API call checks `requireSuperadmin()` on the server. |
| 4 | API key in the browser | ✅ | Built bundle scanned: only the public Supabase anon key, URL and VAPID public key. Service role, SMTP, SMS keys are server-only. |
| 5 | Prompt injection in your AI | ➖ | The app has no AI features. |
| 6 | Admin at signup | ✅ | Sign-up trigger always creates `tenant`; users can only update `full_name, phone` (column grant), never `role`. |
| 7 | Edit the price info | ✅ | Rent is writable only by the owning landlord (RLS). Payments go through `submit_payment` / `confirm_cash_payment`, which check ownership, amount > 0, ≤ 2 years ahead, date not in future. |
| 8 | Login code guessing protection | ✅ | Sign-up codes: limited tries, resend cooldown, hourly cap. **New:** setup codes 5 tries, 7-day expiry (tested). |
| 9 | Query your database | ✅ | RLS enabled on every table; payment/audit tables are read-only to users; anon can only call 4 harmless RPCs. |
| 10 | Environment variables in Git | ✅ | `.gitignore` excludes all `.env*` except the example. **Fixed:** main admin password removed from `12_main_admin.sql` (it was committed; see actions). |
| 11 | Upload a non-photo file | ➖ | The app has no file uploads. |
| 12 | Rate limiting | 🟡 | Sign-up codes, password reset, setup codes, phone sign-in lockout, Supabase Auth limits. No general per-IP limit on Netlify Functions. |

## 2. Architecture & infrastructure (13–25, 47–73)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 13 | Load balancing | ➖ | Handled by Netlify and Supabase. |
| 14 | Reverse proxies | ➖ | Netlify's CDN fronts the site; `/api/*` redirects to functions. |
| 15 | API gateways | ➖ | Netlify redirects act as the gateway; no separate gateway needed. |
| 16 | CI/CD | 🟡 | Netlify deploys on push to `main`. **New:** build runs `npm test && npm run build`. Not yet seen running on Netlify. |
| 17 | Kubernetes | ➖ | Serverless hosting; no containers. |
| 18 | Client-server architecture | ✅ | Vue SPA ↔ Netlify Functions / Supabase. |
| 19 | REST API development | ✅ | JSON endpoints under `/api/*` (Netlify Functions, mirrored in `server/index.js`). |
| 20 | GraphQL | ➖ | Not used. |
| 21 | API documentation | ❌ | Only comments at the top of each function. Add a short API.md if others build on it. |
| 22 | HTTP methods | ✅ | Functions accept POST only (405 otherwise); admin uses PATCH/DELETE. |
| 23 | HTTP status codes | ✅ | 400/401/403/404/405/429/500/503 used correctly. |
| 24 | WebSockets | ✅ | Supabase Realtime for live notifications, payments, tenants. |
| 25 | Server-Sent Events | ➖ | Realtime covers it. |
| 47 | Background jobs | ✅ | Scheduled functions `health-check` (20 min) and `push-sweep`. |
| 48 | Message queues | 🟡 | Notifications table works as a queue (claimed once via `sms_sent_at`). No dedicated queue needed at this size. |
| 49 | Event-driven architecture | 🟡 | Database triggers + Realtime events. |
| 50 | Microservices | ➖ | Small app; one codebase is the right choice. |
| 51 | Monolithic architecture | ✅ | One codebase, shared server modules. |
| 52 | Serverless computing | ✅ | Netlify Functions. |
| 53 | Containerization (Docker) | ➖ | Not needed on Netlify. |
| 54 | Infrastructure as Code | 🟡 | `netlify.toml` + numbered SQL files in Git; Supabase settings are clicked, not coded. |
| 55 | Horizontal scaling | ✅ | Serverless functions scale automatically. |
| 56 | Edge caching | ✅ | `/assets/*` cached 1 year (immutable) on Netlify's CDN. |
| 57 | Cache invalidation | ✅ | Hashed asset names; `sw.js` and manifest `no-cache`. |
| 58 | Feature flags | ❌ | Not built. |
| 59 | Blue-green deployment | 🟡 | Netlify deploys are atomic (new version switches at once). |
| 60 | Canary releases | ❌ | Not available on this plan. |
| 61 | Rolling deployments | ➖ | Atomic deploys instead. |
| 62 | Rollbacks | 🟡 | Netlify → Deploys → pick an older deploy → Publish. Database changes must be reversed by hand. |
| 63 | Health checks | ✅ | Every 20 minutes + "Run checks now" in the admin console. |
| 64 | Liveness & readiness probes | ➖ | No containers; `/api/health` on the Express server. |
| 65 | Monitoring | ✅ | Health checks + app error reports in the admin console. |
| 66 | Logging | ✅ | Netlify Function logs; emails masked in logs (`jo***@gmail.com`). |
| 67 | Distributed tracing | ❌ | Not needed at this size. |
| 68 | Metrics | 🟡 | Admin dashboards (users, payments, installs). |
| 69 | Alerts | 🟡 | Errors and health appear in the admin inbox; no SMS/email alert to the owner. |
| 70 | SLOs | ❌ | Not defined. |
| 71 | SLIs | ❌ | Not defined. |
| 72 | Error budgets | ❌ | Not defined. |
| 73 | Observability | 🟡 | Logs + error reports + health; no tracing. |

## 3. Identity, access & sessions (26–32, 75–77, 111–150)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 26 | Authentication | ✅ | Supabase Auth (email/password, phone via server lookup). |
| 27 | Authorization | ✅ | RLS + server role checks. |
| 28 | Multi-factor authentication | ❌ | Recommended for the main admin first (Supabase supports TOTP). |
| 29 | Password hashing | ✅ | Supabase stores bcrypt hashes; setup codes stored as SHA-256 hashes only (tested). |
| 30 | Session management | ✅ | Supabase JWT (1 h) + refresh token. |
| 31 | RBAC | ✅ | `superadmin` / `landlord` / `tenant`. |
| 32 | ABAC | ✅ | Ownership rules (`landlord_id = auth.uid()`, `my_tenant_id()`). |
| 75 | IAM | ✅ | Database roles `anon` / `authenticated` / `service_role` with explicit grants. |
| 76 | OAuth 2.0 | ➖ | No social sign-in. |
| 77 | JWT rotation | 🟡 | Supabase manages signing keys; rotate in Supabase → Settings → API if leaked. |
| 111 | Email verification | ✅ | 6-character emailed code before the account exists. |
| 112 | Phone number verification | ❌ | Phone numbers are not confirmed by SMS. |
| 113 | Secure registration | ✅ | Code-verified email, role forced to tenant, password rules on the server. |
| 114 | Secure login | ✅ | **Fixed:** first sign-in now needs a one-time setup code (was email/phone only). |
| 115 | Secure logout | ✅ | `supabase.auth.signOut()` clears the session. |
| 116 | Password reset system | ✅ | Emailed single-use link, 60 min, resend cooldown. |
| 117 | Password strength validation | 🟡 | **New:** 8+ characters with letters and numbers on sign-up and tenant setup. Other password screens rely on Supabase: set the same rule there (see actions). |
| 118 | Password expiration policies | ➖ | Forced expiry is no longer recommended (NIST 800-63B). |
| 119 | Account lockout protection | 🟡 | **New:** 5 wrong passwords → 15 min lock on phone sign-in (tested). Email sign-in uses Supabase's built-in limits. |
| 120 | Brute-force login protection | 🟡 | As 119, plus setup code tries. |
| 121 | Login attempt monitoring | 🟡 | `login_failures` table (server only). No dashboard view. |
| 122 | Device session management | ❌ | No "signed-in devices" list. |
| 123 | Active session tracking | ❌ | |
| 124 | Automatic session expiration | 🟡 | Access token expires hourly and refreshes; no idle sign-out. |
| 125 | Concurrent login management | ❌ | |
| 126 | Remember-me security | ➖ | Sessions always persist on the device (mobile-app behaviour). |
| 127 | Secure account recovery | ✅ | Email reset link; lost setup code → admin/landlord issues a new one. |
| 128 | Suspicious login detection | ❌ | |
| 129 | Login notification system | ✅ | Sign-in alerts (`notifySignIn`). |
| 130 | Account deactivation | ✅ | Suspend (ban), delete-account page. |
| 131 | Admin role separation | ✅ | |
| 132 | Landlord role separation | ✅ | |
| 133 | Tenant role separation | ✅ | |
| 134 | Super admin permissions | ✅ | Read-all, managed actions via server; can't delete itself. |
| 135 | Role-based dashboard access | ✅ | Router `meta.role`. |
| 136 | Page-level access control | ✅ | `router.beforeEach` guard. |
| 137 | API-level permission checks | ✅ | `requireSuperadmin`, `requireUserProfile`, landlord check. |
| 138 | Database-level access control | ✅ | RLS + column grants. |
| 139 | Ownership verification | ✅ | In every policy and payment function. |
| 140 | User ID validation | ✅ | IDs come from the verified JWT (`auth.uid()`), never from the request. |
| 141 | Prevent unauthorized account access | ✅ | **Fixed:** setup codes; phone lockout. |
| 142 | Prevent unauthorized record editing | ✅ | **Fixed:** `tenants.user_id` can't be set directly any more. |
| 143 | Prevent unauthorized record deletion | ✅ | Deletes limited by RLS; account deletes server-side with checks. |
| 144 | Admin action restrictions | ✅ | Typed confirmations, can't delete the main admin. |
| 145 | Permission change logging | 🟡 | `admin_audit` entries are written from the app (`adminNote`), not enforced by the server. |
| 146 | Account suspension system | ✅ | |
| 147 | Account ban management | ✅ | Suspend / reactivate. |
| 148 | Privilege escalation prevention | ✅ | Role column locked; `user_id` guard. |
| 149 | Default permission management | ✅ | New users = tenant; tables grant nothing to `anon`. |
| 150 | Access control auditing | 🟡 | This audit; repeat after big changes. |

## 4. Web & API security (78–87, 151–170)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 78 | TLS | ✅ | HTTPS everywhere (Netlify, Supabase). |
| 79 | Encryption at rest | ✅ | Supabase encrypts storage (managed). |
| 80 | Encryption in transit | ✅ | HTTPS + **new** HSTS. |
| 81 | WAF | ❌ | Not on the current plans. |
| 82 | DDoS protection | 🟡 | Platform-level protection from Netlify / Supabase. |
| 83 | CORS | ✅ | Functions send no CORS headers (same-site only); Express limited to `CLIENT_URL`. |
| 84 | CSRF | ✅ | Auth uses Bearer tokens, not cookies, so CSRF doesn't apply. |
| 85 | SQL injection | ✅ | Parameterised queries; dynamic SQL only in setup scripts with fixed names (`%I`). |
| 86 | XSS | ✅ | Escaped output + **new** CSP (`script-src 'self'`). |
| 87 | SSRF | ✅ | Server only calls fixed URLs (Supabase, Resend, Africa's Talking). |
| 151 | Secure HTTP headers | ✅ | **New** in `netlify.toml`: nosniff, X-Frame-Options DENY, Referrer-Policy, Permissions-Policy, COOP. |
| 152 | Content Security Policy | ✅ | **New**, tested locally on /, /login, /signup with no violations. |
| 153 | HSTS | ✅ | **New**: 1 year, subdomains. |
| 154 | Secure cookie configuration | ➖ | The app uses no cookies. |
| 155 | HttpOnly cookies | ➖ | No cookies (session in local storage; CSP limits script access). |
| 156 | SameSite cookies | ➖ | No cookies. |
| 157 | API authentication tokens | ✅ | Supabase JWT in `Authorization: Bearer`. |
| 158 | API token expiration | ✅ | 1 hour. |
| 159 | API token revocation | 🟡 | Sign-out and suspension end sessions; no per-device revoke. |
| 160 | API key rotation | 🟡 | Manual (DEPLOY_KEYS.md); no schedule. |
| 161 | Request origin validation | 🟡 | CORS only. |
| 162 | Request method validation | ✅ | 405 for wrong methods. |
| 163 | Request size limits | ✅ | Netlify 6 MB, Express 100 KB, database truncates long text. |
| 164 | File upload size restrictions | ➖ | No uploads. |
| 165 | File type validation | ➖ | No uploads. |
| 166 | MIME type verification | ➖ | No uploads. |
| 167 | Malware scanning for uploads | ➖ | No uploads. |
| 168 | Secure file storage | ➖ | No uploads. |
| 169 | Directory traversal prevention | ✅ | Static hosting; no file paths from users. |
| 170 | Sensitive information exposure | 🟡 | Server errors now generic; the login page still says whether an email/phone has an account (by design for UX). |

## 5. Database & data (33–46, 88–92, 171–190)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 33 | Database design | ✅ | Normalised tables with foreign keys. |
| 34 | SQL databases | ✅ | PostgreSQL (Supabase). |
| 35 | NoSQL databases | ➖ | Not used. |
| 36 | Database indexing | 🟡 | Key indexes exist; not load-tested. |
| 37 | Database optimization | 🟡 | Phone sign-in reads all profiles with a phone: fine now, slow at thousands of users. |
| 38 | Database transactions | ✅ | Each function runs in one transaction with `for update` locks. |
| 39 | Connection pooling | ✅ | Supabase pooler (managed). |
| 40 | Database replication | ➖ | Supabase plan feature. |
| 41 | Database sharding | ➖ | Not needed. |
| 42 | ORM | ➖ | Supabase query builder + SQL functions. |
| 43 | Input validation | ✅ | Server + database checks. |
| 44 | Data sanitization | ✅ | Trimming, `nullif`, `left()`, HTML escaping. |
| 45 | Error handling | ✅ | `HttpError` with readable messages. |
| 46 | Exception handling | ✅ | try/catch in every function; unknown errors logged, generic message returned. |
| 88 | Database migrations | ✅ | Numbered files + `update_existing.sql`. |
| 89 | Schema versioning | 🟡 | File numbers only; no version table in the database. |
| 90 | Disaster recovery | ❌ | No written plan. |
| 91 | Backups | 🟡 | Depends on the Supabase plan (daily on Pro; none on Free). See actions. |
| 92 | Failover | ➖ | Managed by Supabase. |
| 171 | Database access permissions | ✅ | |
| 172 | Row-Level Security | ✅ | All 21 tables (verified). |
| 173 | Foreign key constraints | ✅ | |
| 174 | Unique constraints | ✅ | |
| 175 | NOT NULL constraints | ✅ | |
| 176 | Data type validation | ✅ | |
| 177 | Database input validation | ✅ | In SQL functions. |
| 178 | Atomic database operations | ✅ | |
| 179 | Transaction rollback | ✅ | Any exception rolls the whole function back. |
| 180 | Duplicate record prevention | ✅ | Unique constraints, one-house-per-tenant trigger. |
| 181 | Duplicate payment prevention | 🟡 | Row locks, ≤3 pending reports, buttons disable while saving; no idempotency key. |
| 182 | Data consistency checks | ✅ | `35_consistency.sql`. |
| 183 | Referential integrity | ✅ | |
| 184 | Soft delete management | ✅ | Tenancies end into Records; archive before clear. |
| 185 | Permanent deletion policies | ✅ | Typed confirmation; delete-account page. |
| 186 | Personal data encryption | 🟡 | Encrypted at rest by the platform; no field-level encryption. |
| 187 | Database audit trails | 🟡 | `admin_audit`, payment receipts, reviewer on each payment. |
| 188 | Database access monitoring | ❌ | Use Supabase → Logs if needed. |
| 189 | Sensitive data masking | ✅ | Emails masked in server logs. |
| 190 | Data retention policies | ❌ | Not defined. |

## 6. Payments (191–210)

Payments are recorded by hand (cash or mobile money sent phone-to-phone) and confirmed by the landlord.
There is no payment gateway, so gateway/webhook items don't apply until one is added.

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 191 | Payment gateway integration security | ➖ | No gateway. |
| 192 | Secure payment request generation | ➖ | No gateway. |
| 193 | Server-side payment verification | ✅ | Only the landlord's confirmation (database function) makes a payment count. |
| 194 | Payment webhook authentication | ➖ | No webhooks. |
| 195 | Webhook signature verification | ➖ | No webhooks. |
| 196 | Payment status validation | ✅ | `pending` → `confirmed` / `rejected` only once. |
| 197 | Payment reference uniqueness | ✅ | UUIDs; per-tenant pay code. |
| 198 | Idempotency keys | ❌ | Add if a gateway is added. |
| 199 | Duplicate transaction prevention | 🟡 | See 181. |
| 200 | Payment timeout handling | ➖ | No gateway. |
| 201 | Failed payment management | ✅ | Reject with reason; tenant notified. |
| 202 | Pending payment management | ✅ | Landlord inbox of payments to confirm. |
| 203 | Payment reconciliation | 🟡 | Landlord checks their phone/cash before confirming. |
| 204 | Transaction history | ✅ | |
| 205 | Payment receipt generation | ✅ | `payment_receipts`. |
| 206 | Refund management | ❌ | |
| 207 | Payment cancellation handling | ✅ | Reject. |
| 208 | Currency validation | ✅ | UGX whole numbers (`bigint`). |
| 209 | Amount manipulation prevention | ✅ | Amount checked in the database; landlord confirms the real amount received. |
| 210 | Financial audit logs | ✅ | Receipts + who reviewed each payment and when. |

## 7. Notifications & OTP (211–225)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 211 | SMS gateway security | ✅ | Africa's Talking keys server-only. |
| 212 | Email gateway security | ✅ | Keys server-only; Resend supported; transactional headers. |
| 213 | OTP verification | ✅ | |
| 214 | OTP expiration | ✅ | Sign-up 20 min; setup codes 7 days. |
| 215 | OTP attempt limits | ✅ | Tested for setup codes. |
| 216 | Notification delivery tracking | 🟡 | `sms_sent_at`; Resend dashboard for email. |
| 217 | Failed SMS retry management | ✅ | Retries up to 2 hours. |
| 218 | Failed email retry management | ❌ | The user taps "Send a new code". |
| 219 | Notification templates | ✅ | |
| 220 | Notification preferences | ❌ | |
| 221 | Notification queue management | 🟡 | See 48. |
| 222 | Duplicate notification prevention | ✅ | Each one claimed once. |
| 223 | Payment confirmation notifications | ✅ | App + SMS. |
| 224 | Account activity notifications | ✅ | Sign-in alerts. |
| 225 | Notification history | ✅ | |

## 8. Frontend, testing & operations (93–110, 226–250)

| # | Item | Status | Evidence / next step |
| --- | --- | --- | --- |
| 93 | Zero Trust architecture | 🟡 | Every request is checked by RLS/server; no network-level zero trust needed. |
| 94 | API versioning | ❌ | |
| 95 | Dependency management | ✅ | Lockfile; **fixed** 4 high vulnerabilities with `overrides` → `npm audit`: 0. |
| 96 | Automated testing | 🟡 | **New:** `npm test` (sign-in security), runs before every deploy. |
| 97 | Unit testing | 🟡 | One suite; add more for payments. |
| 98 | Integration testing | ❌ | |
| 99 | End-to-end testing | ❌ | |
| 100 | Penetration testing | 🟡 | This code audit; no external pen test. |
| 101 | Vulnerability management | 🟡 | `npm audit` run by hand. Turn on GitHub Dependabot. |
| 102 | Software supply chain security | 🟡 | Lockfile + pinned fixes; no signing. |
| 103 | Cloud security | 🟡 | Keys in Netlify env vars; enable MFA on Netlify, Supabase, GitHub accounts. |
| 104 | Multi-tenant architecture | ✅ | Each landlord's data isolated by RLS. |
| 105 | Distributed systems | ➖ | |
| 106 | Eventual consistency | ➖ | One database. |
| 107 | High availability | ➖ | Managed by the platforms. |
| 108 | Performance optimization | ✅ | Compressed images, blurred previews, lazy-loaded pages. |
| 109 | Infrastructure monitoring | 🟡 | Health checks. |
| 110 | Disaster recovery testing | ❌ | |
| 226 | Responsive design testing | 🟡 | Landing page checked at phone and desktop width this session. |
| 227 | Mobile browser compatibility | 🟡 | Not tested on real phones this session. |
| 228 | Desktop browser compatibility | 🟡 | Edge only. |
| 229 | Form validation | ✅ | |
| 230 | Client-side error handling | ✅ | Errors shown in forms; app errors reported. |
| 231 | Server-side error handling | ✅ | |
| 232 | Loading state management | ✅ | Busy states on buttons. |
| 233 | Empty state management | ✅ | |
| 234 | Network failure handling | ✅ | `retryFetch` + clear "network" message. |
| 235 | Offline state detection | ❌ | No offline banner. |
| 236 | Automatic data refresh | ✅ | Realtime. |
| 237 | Double-click submission prevention | ✅ | Buttons disabled while busy. |
| 238 | Accessibility testing | 🟡 | ARIA labels present; no audit run. |
| 239 | Page load optimization | ✅ | |
| 240 | Frontend dependency security | ✅ | `npm audit`: 0. |
| 241 | Automated unit testing | 🟡 | See 96. |
| 242 | Integration testing | ❌ | |
| 243 | End-to-End testing | ❌ | |
| 244 | Security vulnerability scanning | 🟡 | Done by hand in this audit. |
| 245 | Dependency update management | 🟡 | No automatic updates. |
| 246 | Production environment separation | 🟡 | Production keys only in Netlify; local `.env` uses the same Supabase project. |
| 247 | Staging environment testing | ❌ | Use Netlify Deploy Previews + a second Supabase project. |
| 248 | Disaster recovery testing | ❌ | |
| 249 | Application health auditing | ✅ | |
| 250 | Regular security audits | 🟡 | This one; repeat every few months. |

---

## Actions for the owner (can't be done from code)

1. **Run `database/update_existing.sql` in Supabase → SQL Editor.** Adds setup codes, the sign-in lockout and the
   `user_id` guard. Until it runs, registering landlords and giving app access will ask for this update.
2. **Change the main admin password now** (the old one was committed to Git): sign in at `/admin2026` → Settings →
   Password, use 12+ characters. Old commits still contain it, so treat it as public.
3. **Existing first-time accounts:** landlords and tenants who have never signed in now need a setup code. In the
   admin console use *Reset password* on each such landlord; landlords re-give app access where needed.
4. **Supabase → Authentication → Policies / Passwords:** minimum length 8, require letters and digits, turn on
   leaked-password protection. Turn on MFA for the main admin account.
5. **Supabase → Database → Backups:** confirm daily backups (Pro plan) or export weekly by hand.
6. **GitHub:** turn on Dependabot alerts; turn on 2-factor sign-in for GitHub, Netlify and Supabase.
7. **Redeploy on Netlify** after pushing, then check the site loads (new security headers).
