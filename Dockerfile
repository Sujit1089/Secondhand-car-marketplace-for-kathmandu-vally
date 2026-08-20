# ---- deps & build ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm install --no-audit --no-fund
COPY . .
RUN npx prisma generate
RUN npm run build

# ---- production runtime ----
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# Run as non-root user (least privilege — A05 hardening)
RUN apk add --no-cache openssl && addgroup -S appgroup && adduser -S appuser -G appgroup

COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
# Reuse the client generated in the builder stage — the prisma CLI is a
# devDependency and is not present in this stage.
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma

RUN mkdir -p /app/uploads && chown -R appuser:appgroup /app
USER appuser

EXPOSE 4000
CMD ["node", "dist/server.js"]
