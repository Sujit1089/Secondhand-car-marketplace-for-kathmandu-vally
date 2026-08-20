# Setup & Run Guide

## Prerequisites

- Docker Desktop (running)
- Node.js 20+ (only needed if you run outside Docker)
- `openssl` (on Windows: use Git Bash, WSL, or PowerShell's `[guid]::NewGuid()` twice concatenated)

---

## 1. Generate secrets

The backend **refuses to start** with missing, short, or placeholder secrets —
that's an intentional control (A05: Security Misconfiguration), not a bug.

```bash
openssl rand -hex 32   # run this four times
```

Copy the env template and paste one distinct value into each field:

```bash
cp backend/.env.example backend/.env
```

Fill in:
- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `COOKIE_SECRET`
- `CSRF_SECRET`

Then set a database password in **two places that must match**:
- `backend/.env` → inside `DATABASE_URL` (replace `CHANGE_ME_STRONG_DB_PASSWORD`)
- root `.env` → `POSTGRES_PASSWORD`

Finally:

```bash
cp frontend/.env.example frontend/.env
```

---

## 2. Start everything

```bash
docker compose up --build
```

First build takes a few minutes. Wait until you see:

```
🚗 CarMarket NP backend running on port 4000 [production]
```

---

## 3. Create the database schema and seed data

In a **second terminal**:

```bash
docker compose exec backend npx prisma migrate deploy
docker compose exec backend npx tsx prisma/seed.ts
```

If `migrate deploy` reports no migrations exist yet, generate them first:

```bash
docker compose exec backend npx prisma migrate dev --name init
```

---

## 4. Open the app

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Backend health check | http://localhost:4000/health |
| Prisma Studio (DB browser) | `docker compose exec backend npx prisma studio` |

### Seeded accounts (development only)

| Role | Email | Password |
|---|---|---|
| Admin | `admin@carmarket.np` | `SeedPassw0rd!2026` |
| Verified seller | `bikash@example.com` | `SeedPassw0rd!2026` |
| Buyer | `buyer@example.com` | `SeedPassw0rd!2026` |
| Pending KYC | `pending@example.com` | `SeedPassw0rd!2026` |

---

## 5. Demo script for the viva

This sequence demonstrates every security claim in about five minutes.

**A. Show the absence of phone numbers**
1. Open any listing while logged out.
2. Open DevTools → Network → the `/api/listings/:id` response.
3. Point out there is no `phone` or `email` field anywhere in the JSON. The
   data is not hidden by CSS — it is never served.

**B. Show end-to-end encryption working**
1. Log in as the buyer in a normal window, and as `bikash@example.com` in a
   private window.
2. Buyer opens one of Bikash's listings → **Message the seller** → send a message.
3. Watch it arrive in real time in the other window.
4. Now open the database:
   ```bash
   docker compose exec db psql -U carmarket_user -d carmarket_np -c 'SELECT "ciphertext", "nonce" FROM "Message" LIMIT 5;'
   ```
   The stored rows are base64 blobs. **This is the strongest single piece of
   evidence for the thesis** — screenshot it next to the readable chat window.

**C. Show identity gating**
1. Log in as `buyer@example.com` (KYC not submitted) → go to **List a car**.
2. The route refuses and redirects to identity verification. Show that this is
   enforced server-side too:
   ```bash
   curl -i -X POST http://localhost:4000/api/listings
   ```

**D. Show the moderation workflow**
1. Log in as admin → **Identity queue** → approve `pending@example.com`.
2. **Listings to review** → open a bluebook → approve and publish.
3. Show the two seeded `PENDING_REVIEW` listings appearing publicly after approval.

**E. Show the audit trail**
1. Deliberately fail a login five times with any account.
2. Admin → **Audit trail** → the `USER_LOGIN_FAILED` entries and the final
   `USER_LOCKED` entry appear with IP addresses.
3. The dashboard's "Failed logins 24h" counter increments.

---

## 6. Common issues

**`Invalid environment configuration` on startup**
A secret is missing or under 32 characters. Re-run `openssl rand -hex 32`.

**`JWT_ACCESS_SECRET looks like a placeholder value`**
The `.env.example` text is still in place. Replace it with a generated value.

**Backend can't reach the database**
The password in `DATABASE_URL` and `POSTGRES_PASSWORD` don't match. They must
be identical.

**CORS errors in the browser console**
`CORS_ORIGIN` in `backend/.env` must exactly match the frontend URL, including
protocol and port: `http://localhost:3000` (no trailing slash).

**Images don't display**
Uploads are served through an authenticated route, not statically. Confirm the
backend is reachable and `NEXT_PUBLIC_API_URL` is correct in `frontend/.env`.

**Messages show "can't be decrypted on this device"**
Expected if you logged out (which wipes the private key) or you're on a
different browser/device. This is correct end-to-end behaviour, not a fault —
and it's worth explaining during the defense.

**Port already in use**
Change the host-side port in `docker-compose.yml`, e.g. `"3001:3000"`.

---

## 7. Running the penetration test

With the app running, the tooling for the testing chapter:

```bash
# Dependency vulnerabilities
docker compose exec backend npm audit --audit-level=high

# Security headers
curl -I http://localhost:4000/health

# Rate limiting (expect HTTP 429 partway through)
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST http://localhost:4000/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"buyer@example.com","password":"wrong"}'
done
```

For OWASP ZAP or Burp Suite, point the proxy at `http://localhost:3000` and
run an authenticated scan using a logged-in session. Test cases per OWASP
category are listed in `docs/OWASP-MAPPING.md`.
