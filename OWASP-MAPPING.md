# OWASP Top 10 (2021) — Control Mapping

This document maps every OWASP Top 10 (2021) category to the specific
controls implemented in this system, with file references. It is written to
be used directly as source material for the thesis's *Proposed Solution* and
*Results/Findings* chapters, and as the checklist the penetration test is
executed against.

---

## A01:2021 — Broken Access Control

**Risk in this domain:** A buyer reads another buyer's private negotiation; a
seller edits a rival's listing; anyone downloads another user's citizenship
document by guessing a filename.

| Control | Implementation | File |
|---|---|---|
| Ownership verification on every mutation | `listing.sellerId !== userId` → 403 before any update/delete | `controllers/listing.controller.ts` |
| Conversation participant check | `assertParticipant()` gates every message read/write | `controllers/conversation.controller.ts` |
| Socket room authorization | DB check that the user is buyer or seller before `socket.join()` | `sockets/chat.socket.ts` |
| Non-public listing visibility | Non-`ACTIVE` listings return 404 to non-owners (not 403 — avoids confirming existence) | `controllers/listing.controller.ts` |
| Authenticated file serving | KYC/bluebook documents served through an authorization check, never as static files | `controllers/user.controller.ts` → `serveUpload` |
| Path traversal prevention | `resolveStoredPath()` rejects any resolved path outside the upload root | `middlewares/upload.middleware.ts` |
| Role-based access control | `requireRole(ADMIN)` applied at router level, not per-route | `routes/admin.routes.ts` |
| Stale authorization prevention | User role/KYC/lock state re-read from DB on every request rather than trusted from the JWT | `middlewares/auth.middleware.ts` |
| Deny-by-default | `requireAuth` applied via `router.use()` on all messaging/admin routers | `routes/*.routes.ts` |

**Pentest cases:** IDOR on `/api/listings/:id` (PATCH another user's listing),
IDOR on `/api/conversations/:id/messages`, path traversal on
`/api/users/files/../../.env`, privilege escalation by sending `role: "ADMIN"`
in a registration or profile-update body.

---

## A02:2021 — Cryptographic Failures

**Risk in this domain:** Conversation contents (containing meeting locations,
phone numbers voluntarily exchanged, price negotiations) exposed by a
database breach; session tokens stolen and replayed.

| Control | Implementation | File |
|---|---|---|
| End-to-end encrypted messaging | X25519 key exchange + XSalsa20-Poly1305 (libsodium), performed client-side; server stores only `ciphertext` + `nonce` | `prisma/schema.prisma` (`Message`), frontend crypto module |
| Private keys never transmitted | Only `chatPublicKey` is sent to the server; private key generated in-browser and held in IndexedDB | `controllers/user.controller.ts` → `registerChatPublicKey` |
| Password hashing | bcrypt, cost factor 12 (configurable, floor of 10 enforced) | `config/env.ts`, `controllers/auth.controller.ts` |
| Refresh tokens stored hashed | SHA-256 of the token persisted; raw value never written to the DB | `services/token.service.ts` |
| Single-use tokens hashed | Email-verify and password-reset tokens stored as SHA-256 digests | `controllers/auth.controller.ts` |
| Minimal JWT payload | Token carries only `sub` and `role` — no email, name, or KYC state (JWTs are encoded, not encrypted) | `services/token.service.ts` |
| Algorithm pinning | `algorithms: ["HS256"]` on verify — blocks `alg: none` and algorithm-confusion attacks | `services/token.service.ts` |
| TLS enforcement | HSTS (2 years, includeSubDomains, preload) and `upgrade-insecure-requests` in production | `app.ts` |
| Secure cookie flags | `httpOnly`, `secure` (prod), `sameSite: strict`, scoped paths | `services/token.service.ts` |

**Pentest cases:** Inspect the `Message` table directly and confirm no
plaintext is recoverable; attempt an `alg: none` JWT forgery; confirm
`Set-Cookie` flags; confirm no token is present in `localStorage`.

---

## A03:2021 — Injection

**Risk in this domain:** SQL injection through search filters; stored XSS in a
listing description that fires in another user's browser.

| Control | Implementation | File |
|---|---|---|
| Parameterized queries | Prisma ORM — no raw SQL string concatenation anywhere in the codebase | all controllers |
| Schema-based input validation | Zod schemas on body/query/params for every endpoint | `validators/*.ts`, `middlewares/validate.ts` |
| Mass-assignment prevention | `.strict()` on every schema — unknown keys are rejected outright | `validators/*.ts` |
| Bounded search parameters | Typed, range-checked filters; `limit` hard-capped at 50 | `validators/listing.validator.ts` |
| XSS output encoding | React escapes interpolated values by default; no `dangerouslySetInnerHTML` used | frontend |
| Content Security Policy | `script-src 'self'`, `object-src 'none'`, `frame-ancestors 'none'` | `app.ts` |
| Email template escaping | `escapeHtml()` applied to user-controlled names before HTML interpolation | `services/mail.service.ts` |
| HTTP parameter pollution | `hpp()` middleware | `app.ts` |
| SVG upload blocked | SVG excluded from the MIME allowlist (XML, can carry script) | `middlewares/upload.middleware.ts` |

**Pentest cases:** SQLi payloads in every search filter and in the login form;
stored XSS payloads (`<img src=x onerror=...>`) in listing title/description;
NoSQL-style operator injection in JSON bodies; SVG upload attempt.

---

## A04:2021 — Insecure Design

**Risk in this domain:** The two headline fraud patterns — scrapeable contact
details and advance-payment scams — are *design* failures in existing
platforms, not implementation bugs.

| Control | Implementation | File |
|---|---|---|
| No public contact details, by design | No API endpoint returns a seller's phone or email to another user; there is no code path to leak | `controllers/listing.controller.ts`, `user.controller.ts` |
| Identity binding before listing | `requireApprovedKyc` gates listing creation — no anonymous account can advertise | `routes/listing.routes.ts` |
| Document verification workflow | Listings enter `PENDING_REVIEW`; admin cross-checks the bluebook name against verified identity | `controllers/admin.controller.ts` |
| Re-review on material edit | Changing price/plate/bluebook on a live listing resets it to `PENDING_REVIEW` — prevents approve-then-swap | `controllers/listing.controller.ts` |
| Distinct-reporter auto-flagging | Listing hidden after 3 *distinct* reporters, so one malicious actor cannot take down a rival | `controllers/report.controller.ts` |
| Report-flooding prevention | One open report per reporter per target; hourly rate limit | `controllers/report.controller.ts`, `config/rateLimiters.ts` |
| Tiered rate limiting | Separate, stricter limits for auth, upload, and report endpoints | `config/rateLimiters.ts` |
| Plate number masking | Public views show a partially masked plate (quasi-identifier protection) | `controllers/listing.controller.ts` → `maskPlate` |
| Soft deletion | Listings are marked `REMOVED`, never destroyed — preserves evidence after a dispute | `controllers/listing.controller.ts` |

**Pentest cases:** Attempt to obtain any seller phone number through any
endpoint or response body; attempt to publish a listing without KYC; attempt
to self-approve KYC; attempt to un-flag a listing as a normal user.

---

## A05:2021 — Security Misconfiguration

| Control | Implementation | File |
|---|---|---|
| Fail-fast env validation | Zod-validated env; app refuses to boot on missing/short secrets | `config/env.ts` |
| Placeholder-secret rejection | Boot fails if a secret contains `changeme`, `example`, etc. | `config/env.ts` |
| Security headers | Helmet: CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy: no-referrer`, `frame-ancestors 'none'` | `app.ts` |
| CORS allowlist | Explicit origin list; wildcard never used with `credentials: true` | `app.ts` |
| Error message sanitization | Central handler; stack traces and internals never reach the client | `middlewares/errorHandler.ts` |
| Request size limits | 1 MB JSON/urlencoded cap; 5 MB per uploaded file | `app.ts`, `config/env.ts` |
| Non-root container | Docker image runs as unprivileged `appuser` | `backend/Dockerfile` |
| Multi-stage build | Build toolchain excluded from the runtime image | `backend/Dockerfile` |
| Secrets excluded from VCS | `.env` in `.gitignore`; `.env.example` documents required keys with no real values | `.gitignore` |
| `x-powered-by` removed | Helmet removes the header (reduces fingerprinting) | `app.ts` |

**Pentest cases:** Header inspection (securityheaders.io equivalent); attempt
boot with a weak secret; force a 500 and inspect the response body; scan for
directory listing on the uploads path.

---

## A06:2021 — Vulnerable and Outdated Components

| Control | Implementation |
|---|---|
| Dependency audit script | `npm run audit:check` (`--audit-level=high`) |
| Pinned major versions | Caret ranges within reviewed majors in `package.json` |
| Minimal dependency surface | No unmaintained or single-purpose micro-packages where a standard library suffices |
| Alpine base images | `node:20-alpine`, `postgres:16-alpine`, `redis:7-alpine` — smaller attack surface |

**Pentest cases:** `npm audit`, `docker scout`/Trivy image scan, check for
known CVEs in the declared dependency tree. Document the result table in the
Findings chapter.

---

## A07:2021 — Identification and Authentication Failures

| Control | Implementation | File |
|---|---|---|
| Account lockout | 5 failed attempts → 15-minute lock | `controllers/auth.controller.ts` |
| Rate limiting on auth | 8 attempts per IP per 15 minutes | `config/rateLimiters.ts` |
| Strong password policy | ≥12 chars, mixed case, digit, special character | `validators/auth.validator.ts` |
| User-enumeration prevention | Identical responses for existing vs. non-existing accounts on register, login, and password reset | `controllers/auth.controller.ts` |
| Timing-attack mitigation | Dummy bcrypt comparison on the "user not found" path | `controllers/auth.controller.ts` |
| Refresh token rotation | Every use revokes the old token and issues a new one | `services/token.service.ts` |
| Token reuse detection | Replay of a revoked token revokes the entire token family and raises an audit event | `services/token.service.ts` |
| Short access-token lifetime | 15 minutes | `config/env.ts` |
| Session invalidation on credential change | All refresh tokens revoked on password reset/change | `controllers/auth.controller.ts` |
| Session invalidation on suspension | Admin suspension revokes tokens immediately | `controllers/admin.controller.ts` |
| Email verification required | Gated actions require `isEmailVerified` | `middlewares/auth.middleware.ts` |

**Pentest cases:** Hydra/Burp Intruder credential-guessing run against
`/api/auth/login` (expect lockout + 429); timing analysis of valid vs.
invalid emails; refresh-token replay test; confirm old sessions die after a
password change.

---

## A08:2021 — Software and Data Integrity Failures

| Control | Implementation | File |
|---|---|---|
| CSRF protection | Double-submit cookie pattern with `X-CSRF-Token` header verification | `config/csrf.ts` |
| `sameSite: strict` cookies | Blocks cross-site cookie transmission | `services/token.service.ts` |
| Upload content verification | Magic-byte (file signature) check after write; mismatched files deleted | `middlewares/upload.middleware.ts` |
| Client filename discarded | Server-generated random filenames — defeats double-extension and traversal tricks | `middlewares/upload.middleware.ts` |
| MIME/extension cross-check | Declared type must match the extension allowlist | `middlewares/upload.middleware.ts` |
| Message authenticity | XSalsa20-Poly1305 is AEAD — a tampered ciphertext fails authentication on decrypt | frontend crypto module |
| Lockfile-based installs | `npm ci` in Docker builds (reproducible dependency tree) | `backend/Dockerfile` |

**Pentest cases:** CSRF proof-of-concept form against a state-changing
endpoint; upload `shell.php.jpg`; upload a PHP file with a spoofed
`Content-Type: image/jpeg`; upload a polyglot; tamper with a stored
ciphertext and confirm decryption fails client-side.

---

## A09:2021 — Security Logging and Monitoring Failures

| Control | Implementation | File |
|---|---|---|
| Append-only audit log | `AuditLog` table records auth events, KYC decisions, listing status changes, reports, admin actions | `prisma/schema.prisma`, `services/audit.service.ts` |
| Actor attribution | Admin actions log the acting admin, not just the subject | `controllers/admin.controller.ts` |
| Attack-signal capture | Failed logins, lockouts, and token-reuse events are all logged | `controllers/auth.controller.ts`, `services/token.service.ts` |
| PII redaction in logs | Passwords, tokens, citizenship numbers, and **message ciphertext** are redacted from application logs | `config/logger.ts` |
| Content never logged | Message plaintext is unavailable to the server by construction; ciphertext is redacted from logs as defense in depth | `config/logger.ts` |
| Security metrics surfaced | Admin dashboard reports 24h failed logins and token-reuse detections | `controllers/admin.controller.ts` |
| Logging never breaks requests | Audit writes are fire-and-forget with internal error capture | `services/audit.service.ts` |

**Pentest cases:** Run an attack (brute force, IDOR attempt, token replay),
then confirm each produced a corresponding audit record with correct IP and
attribution. Screenshot the dashboard security counters before/after — this
is strong Findings-chapter evidence.

---

## A10:2021 — Server-Side Request Forgery (SSRF)

| Control | Implementation |
|---|---|
| No user-supplied URL fetching | The application makes no outbound HTTP request based on user input. Images are uploaded directly, never fetched from a supplied URL. |
| No URL-based image import | Deliberately excluded from scope — a "import photo from URL" feature would introduce SSRF; documented as an intentional design exclusion. |
| Network segmentation | Docker bridge network; Postgres and Redis are not exposed to the public network in the production compose profile. |

**Pentest case:** Confirm no endpoint accepts a URL parameter that triggers a
server-side fetch. Document as "not applicable by design" with justification —
this is a legitimate and defensible finding, not a gap.

---

## Additional controls beyond the Top 10

| Concern | Control |
|---|---|
| Denial of service | Request size caps, bounded pagination, socket payload cap, tiered rate limits |
| Data minimization (privacy) | Public endpoints expose no phone/email; plate numbers masked; KYC images access-controlled |
| Non-repudiation | Full audit trail with actor, IP, user-agent, and timestamp |
| Least privilege | Non-root container user; admin role separated from user role; refresh cookie path-scoped to `/api/auth` |
| Fail-safe defaults | Listings default to `PENDING_REVIEW`; KYC defaults to `NOT_SUBMITTED`; upload validation fails closed |

---

## Regulatory alignment

Nepal has no direct GDPR equivalent, but the following are applicable and
should be cited in the thesis's Compliance section:

- **Individual Privacy Act, 2075 (2018), Nepal** — governs collection and
  protection of personal data; directly relevant to KYC document handling.
- **Electronic Transactions Act, 2063 (2008), Nepal** — governs electronic
  records, digital signatures, and computer-related offences.
- **ISO/IEC 27001:2022** — the control families implemented here map to
  A.5 (policies), A.8 (asset/access management), A.8.24 (cryptography),
  A.8.15 (logging), and A.8.16 (monitoring).
- **GDPR (as international best practice)** — data minimization (Art. 5(1)(c))
  and security of processing (Art. 32) are the principles the PII-minimization
  and encryption design follow, cited as a benchmark rather than a binding
  obligation.
