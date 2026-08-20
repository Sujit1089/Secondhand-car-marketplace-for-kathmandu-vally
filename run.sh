#!/usr/bin/env bash
# ============================================================================
# run.sh — Sirjana Auto: one-command development launcher
#
# Usage:
#   ./run.sh              Start everything (DB + backend + frontend)
#   ./run.sh docker       Start everything inside Docker containers
#   ./run.sh db           Start only Postgres + Redis in Docker
#   ./run.sh backend      Start only the backend (assumes DB is running)
#   ./run.sh frontend     Start only the Next.js dev server
#   ./run.sh seed         Seed the database (DB must be running)
#   ./run.sh migrate      Run Prisma migrations only
#   ./run.sh stop         Stop all Docker containers
#   ./run.sh status       Show status of running services
#   ./run.sh logs         Tail logs from Docker containers
# ============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
CERTS_DIR="$PROJECT_DIR/nginx/certs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[i]${NC} $*"; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ---------------------------------------------------------------------------
# Detect docker compose command (v2 plugin or v1 standalone)
# ---------------------------------------------------------------------------
DC=""  # will be set by check_docker

check_docker() {
  if ! command -v docker &>/dev/null; then
    err "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
    exit 1
  fi
  if ! docker info &>/dev/null 2>&1; then
    err "Docker daemon is not running. Start Docker and try again."
    exit 1
  fi

  # Prefer `docker compose` (v2 plugin), fall back to `docker-compose` (v1)
  if docker compose version &>/dev/null 2>&1; then
    DC="docker compose"
  elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
  else
    err "Neither 'docker compose' nor 'docker-compose' found."
    exit 1
  fi
}

check_node() {
  if ! command -v node &>/dev/null; then
    err "Node.js is not installed. Install Node 20+ from https://nodejs.org/"
    exit 1
  fi
}

check_npm() {
  if ! command -v npm &>/dev/null; then
    err "npm is not installed."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Self-signed TLS certificates for nginx (development only)
# ---------------------------------------------------------------------------
generate_certs() {
  if [ -f "$CERTS_DIR/localhost.crt" ] && [ -f "$CERTS_DIR/localhost.key" ]; then
    return 0
  fi

  header "Generating self-signed TLS certificates"
  mkdir -p "$CERTS_DIR"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERTS_DIR/localhost.key" \
    -out "$CERTS_DIR/localhost.crt" \
    -subj "/C=NP/ST=Baghmati/L=Kathmandu/O=SirjanaAuto/CN=localhost" \
    2>/dev/null
  log "Self-signed certs created at $CERTS_DIR/"
}

# ---------------------------------------------------------------------------
# Docker services (DB + Redis)
# ---------------------------------------------------------------------------
start_db() {
  header "Starting database services"
  check_docker
  generate_certs

  cd "$PROJECT_DIR"
  $DC up -d db redis

  info "Waiting for PostgreSQL to be healthy..."
  local retries=30
  while [ $retries -gt 0 ]; do
    if $DC exec -T db pg_isready -U carmarket_user -d carmarket_np &>/dev/null; then
      log "PostgreSQL is ready"
      break
    fi
    retries=$((retries - 1))
    sleep 1
  done
  if [ $retries -eq 0 ]; then
    err "PostgreSQL did not become healthy in time"
    exit 1
  fi

  log "Redis is running"
}

stop_all() {
  header "Stopping all containers"
  check_docker
  cd "$PROJECT_DIR"
  $DC down
  log "All containers stopped"
}

# ---------------------------------------------------------------------------
# Backend setup
# ---------------------------------------------------------------------------
setup_backend() {
  header "Setting up backend"
  check_node
  check_npm

  cd "$BACKEND_DIR"

  if [ ! -d "node_modules" ]; then
    info "Installing backend dependencies..."
    npm install --no-audit --no-fund
  fi

  info "Generating Prisma client..."
  npx prisma generate 2>/dev/null || true

  info "Running database migrations..."
  npx prisma migrate dev 2>/dev/null || true

  log "Backend ready"
}

start_backend() {
  header "Starting backend dev server"
  check_node

  cd "$BACKEND_DIR"
  log "Backend starting on http://localhost:4000"
  exec npm run dev
}

# ---------------------------------------------------------------------------
# Frontend setup
# ---------------------------------------------------------------------------
setup_frontend() {
  header "Setting up frontend"
  check_node
  check_npm

  cd "$FRONTEND_DIR"

  if [ ! -d "node_modules" ]; then
    info "Installing frontend dependencies..."
    npm install --no-audit --no-fund
  fi

  log "Frontend ready"
}

start_frontend() {
  header "Starting frontend dev server"
  check_node

  cd "$FRONTEND_DIR"
  log "Frontend starting on http://localhost:3000"
  exec npm run dev
}

# ---------------------------------------------------------------------------
# Seed
# ---------------------------------------------------------------------------
run_seed() {
  header "Seeding database"
  check_node

  cd "$BACKEND_DIR"
  info "Running seed script..."
  npx tsx prisma/seed.ts
  log "Database seeded"
}

# ---------------------------------------------------------------------------
# Full Docker mode
# ---------------------------------------------------------------------------
start_docker() {
  header "Starting everything in Docker"
  check_docker
  generate_certs

  cd "$PROJECT_DIR"

  info "Building and starting all containers..."
  $DC up -d --build

  info "Waiting for services to be ready..."
  local retries=40
  while [ $retries -gt 0 ]; do
    if $DC exec -T db pg_isready -U carmarket_user -d carmarket_np &>/dev/null 2>&1; then
      break
    fi
    retries=$((retries - 1))
    sleep 2
  done

  if [ $retries -eq 0 ]; then
    warn "DB may still be starting up. Check with: $DC logs db"
  fi

  echo ""
  log "All services started!"
  echo ""
  info "  Frontend:  http://localhost:3000"
  info "  Backend:   http://localhost:4000"
  info "  Proxy:     http://localhost:80"
  info "  Database:  localhost:5432"
  echo ""
  info "Logs:    $DC logs -f"
  info "Stop:    $DC down"
  echo ""
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
  header "Service Status"
  check_docker
  cd "$PROJECT_DIR"
  $DC ps
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
show_logs() {
  check_docker
  cd "$PROJECT_DIR"
  $DC logs -f --tail=50
}

# ---------------------------------------------------------------------------
# Print help
# ---------------------------------------------------------------------------
print_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗"
  echo -e "  ║     🚗  Sirjana Auto  —  सिर्जना अटो     ║"
  echo -e "  ║  Secure Second-Hand Car Marketplace      ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
}

print_help() {
  echo -e "${BOLD}Usage:${NC}"
  echo "  ./run.sh              Start full dev environment (DB + backend + frontend)"
  echo "  ./run.sh docker       Start everything inside Docker containers"
  echo "  ./run.sh db           Start only Postgres + Redis in Docker"
  echo "  ./run.sh backend      Start only the backend server"
  echo "  ./run.sh frontend     Start only the Next.js frontend"
  echo "  ./run.sh seed         Seed the database with demo data"
  echo "  ./run.sh migrate      Run Prisma migrations"
  echo "  ./run.sh stop         Stop all Docker containers"
  echo "  ./run.sh status       Show running service status"
  echo "  ./run.sh logs         Tail Docker container logs"
  echo "  ./run.sh help         Show this help message"
  echo ""
  echo -e "${BOLD}Default demo accounts:${NC}"
  echo "  Admin:   admin@carmarket.np   / SeedPassw0rd!2026"
  echo "  Vendor:  bikash@example.com   / SeedPassw0rd!2026"
  echo "  Buyer:   buyer@example.com    / SeedPassw0rd!2026"
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print_banner

case "${1:-}" in
  help|-h|--help)
    print_help
    ;;
  docker)
    start_docker
    ;;
  db)
    start_db
    ;;
  backend)
    start_db
    setup_backend
    start_backend
    ;;
  frontend)
    setup_frontend
    start_frontend
    ;;
  seed)
    run_seed
    ;;
  migrate)
    cd "$BACKEND_DIR"
    npx prisma migrate dev
    ;;
  stop)
    stop_all
    ;;
  status)
    show_status
    ;;
  logs)
    show_logs
    ;;
  help|-h|--help)
    print_help
    ;;
  "")
    # Default: start everything in dev mode
    DOCKER_STARTED=false

    start_db
    DOCKER_STARTED=true
    setup_backend
    setup_frontend

    header "Starting development servers"

    info "Backend → http://localhost:4000"
    info "Frontend → http://localhost:3000"
    echo ""

    # Start backend in background
    cd "$BACKEND_DIR"
    npm run dev &
    BACKEND_PID=$!

    # Start frontend in background
    cd "$FRONTEND_DIR"
    npm run dev &
    FRONTEND_PID=$!

    # Cleanup on Ctrl+C / SIGTERM / SIGHUP
    cleanup() {
      echo ""
      warn "Shutting down development servers..."
      kill $BACKEND_PID $FRONTEND_PID 2>/dev/null || true
      wait $BACKEND_PID $FRONTEND_PID 2>/dev/null || true
      log "Development servers stopped"

      if [ "$DOCKER_STARTED" = true ]; then
        header "Stopping Docker containers"
        cd "$PROJECT_DIR"
        $DC down
        log "Docker containers stopped"
      fi

      echo ""
      log "All clean. Bye!"
    }
    trap cleanup INT TERM HUP EXIT

    log "Both servers running. Press Ctrl+C to stop."
    wait
    ;;
  *)
    err "Unknown command: $1"
    print_help
    exit 1
    ;;
esac
