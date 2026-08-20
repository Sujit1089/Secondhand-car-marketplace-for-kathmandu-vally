# Secure Second-Hand Car Marketplace for Kathmandu Valley

A production-oriented C2C car marketplace for the Kathmandu Valley, built as
the technical artifact for a Cyber Security Project thesis. The system is
designed around two concrete, observed failure modes in existing Nepali
classifieds platforms (HamroBazar, OLX Nepal, etc.):

1. **Unprotected PII exposure** — phone numbers rendered in plaintext to any
   visitor, enabling scraping, spam, and harassment.
2. **Advance-payment fraud** — no seller accountability or identity binding,
   so a buyer who sends a deposit has no recourse if the seller disappears.

## How this system addresses them

| Problem | Mitigation | Where |
|---|---|---|
| Public phone number scraping | No raw phone numbers ever rendered client-side. All contact happens through in-app **end-to-end encrypted chat**. | `sockets/chat.socket.ts`, frontend chat module |
| Advance-payment / vanishing-seller fraud | Seller **KYC verification** (citizenship ID + bluebook cross-check) required before a listing goes live; every action is written to an immutable **audit log**; a **report/flagging** system with rate-limited abuse controls | `User.kycStatus`, `AuditLog` model, `report.routes.ts` |
| Fake/mismatched vehicle documents | Bluebook image + registration number captured per listing, admin-reviewed before `ACTIVE` status | `Listing` model |
| Credential stuffing / brute force | Tiered rate limiting, account lockout after failed attempts, bcrypt cost factor 12 | `config/rateLimiters.ts`, `User.failedLoginCount` |
| Session/token theft (XSS) | JWT access token in `httpOnly` cookie, never `localStorage`; CSP restricts script sources | `app.ts` helmet config |
| CSRF (since we use cookies) | Double-submit CSRF cookie pattern, `sameSite=strict` | `config/csrf.ts` |
| CSRF/session riding via forged cross-origin requests | Strict CORS allowlist (no wildcard `*` with credentials) | `app.ts` |
| Refresh token replay | Refresh tokens stored **hashed only**, rotated on use, reuse triggers full session revocation | `RefreshToken` model (rotation logic in Stage 2) |
| Info leakage via error responses | Centralized error handler strips stack traces/internals from client responses | `middlewares/errorHandler.ts` |
| Boot-time misconfiguration (weak/default secrets) | Zod-validated env schema; app refuses to start with short/placeholder secrets | `config/env.ts` |

## Why end-to-end encrypted chat, not just TLS

TLS protects data in transit but the **server itself** can still read every
message (and a DB compromise or subpoena/insider-access scenario would
expose full conversation history — including negotiation details, meeting
locations, and personal information exchanged between strangers). Given the
threat model here (protecting two private individuals transacting with each
other, not a business needing moderation visibility), true E2E encryption is
the stronger and more defensible design:

- Each user generates an **X25519 keypair client-side** on first chat use.
- Only the **public key** is ever sent to the server (`User.chatPublicKey`).
- Messages are encrypted client-side (X25519 key exchange → XSalsa20-Poly1305
  via libsodium) before leaving the browser.
- The server (`Message.ciphertext`, `Message.nonce`) stores and relays
  opaque blobs it cannot decrypt — verifiable in the pentest chapter by
  inspecting DB contents directly.
- Private keys never leave the client (stored in IndexedDB), so losing
  server access (breach, compromised admin, legal request) does not expose
  historical conversations.

## Nepal-specific data modeling

- `Province` enum uses Nepal's 7 federal provinces; listings capture
  district/municipality/ward for Kathmandu Valley granularity.
- `Listing.plateNumber` / `bluebookRegNumber` / `bluebookImageUrl` model the
  **Bluebook (नीलपुस्तिका)**, Nepal's vehicle registration document — the
  central trust artifact in a used-car transaction, and the most common
  fraud vector (mismatched/forged documents).
- No payment/escrow system is implemented by design — since the security
  contribution is the encrypted communication and identity-verification
  layer, not a financial rail. This scope decision is documented in the
  thesis's Scope/Limitations section.
- Brand/model taxonomy (seed data, Stage 3) reflects locally dominant
  brands: Suzuki, Hyundai, Toyota, Kia, Tata, Mahindra, Honda.

## Stack

- **Backend**: Node.js + Express + TypeScript, PostgreSQL + Prisma ORM, Redis
  (rate-limit store / session support), Socket.IO (encrypted chat relay)
- **Frontend**: Next.js 14 + TypeScript + Tailwind CSS, libsodium-wrappers
  (client-side crypto)
- **Infra**: Docker Compose (Postgres, Redis, backend, frontend), designed to
  sit behind an nginx/TLS reverse proxy in production

## Project status (build stages)

- [x] Stage 1 — Monorepo scaffold, Prisma schema, security middleware
      backbone (helmet/CORS/CSRF/rate-limiting/error handling), Docker Compose
- [ ] Stage 2 — Auth module (register/login/JWT rotation/KYC upload), input
      validation layer
- [ ] Stage 3 — Listings CRUD + search, encrypted chat implementation,
      reporting/admin moderation
- [ ] Stage 4 — Frontend (Next.js) pages
- [ ] Stage 5 — Security hardening pass + OWASP Top 10 mapping doc
- [ ] Stage 6 — Penetration test execution + report

## Local setup

```bash
cp backend/.env.example backend/.env   # fill in generated secrets
cp frontend/.env.example frontend/.env
openssl rand -hex 32                   # run 4x for the 4 secret fields

docker compose up --build
```

Backend: http://localhost:4000/health
Frontend: http://localhost:3000
