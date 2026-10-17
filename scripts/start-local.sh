#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
COMPOSE_DIR="$ROOT_DIR/backend/local"
AP_DIR="$ROOT_DIR/ai-platform"
ABO_DIR="$ROOT_DIR/abo"
VIEWER_DIR="$ROOT_DIR/ai-platform-viewer"
STATE_DIR="$ROOT_DIR/.wrangler/dev-stack"
LOG_DIR="$STATE_DIR/logs"
PID_DIR="$STATE_DIR/pids"

AP_PORT="${AI_PLATFORM_PORT:-8787}"
ABO_PORT="${ABO_PORT:-8788}"
VIEWER_PORT="${AI_PLATFORM_VIEWER_PORT:-5173}"
SUPABASE_PORT="${SUPABASE_HTTP_PORT:-54321}"
START_TIMEOUT="${START_TIMEOUT_SECONDS:-120}"

AP_URL="http://127.0.0.1:$AP_PORT"
ABO_URL="http://127.0.0.1:$ABO_PORT"
VIEWER_URL="http://127.0.0.1:$VIEWER_PORT"
SUPABASE_URL="http://127.0.0.1:$SUPABASE_PORT"

RUN_LOG_DIR=""
STARTED_SUPABASE=0
SUPABASE_WAS_READY=0
INCLUDE_VIEWER=1
declare -a STARTED_PGIDS=()
declare -a TAIL_PIDS=()

usage() {
  cat <<'EOF'
Start or manage the local non-Flutter AiClinic development stack.

Usage:
  ./scripts/start-local.sh [start] [--no-viewer]
  ./scripts/start-local.sh status
  ./scripts/start-local.sh stop

Starts/reuses local Supabase, AP (ai-platform), ABO, and the AI Platform
Viewer. It applies pending Supabase and D1 migrations without resetting data.
Ctrl-C stops only processes and the Compose stack started by this invocation.
`stop` also cleans up services left behind by a force-killed invocation.

Ports can be changed with SUPABASE_HTTP_PORT, AI_PLATFORM_PORT, ABO_PORT,
AI_PLATFORM_VIEWER_PORT, and START_TIMEOUT_SECONDS.
EOF
}

log() { printf '[local-stack] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

http_status() {
  local url="$1"
  shift
  curl --silent --show-error --max-time 3 -o /dev/null -w '%{http_code}' "$@" "$url" 2>/dev/null || true
}

port_open() {
  timeout 1 bash -c '>/dev/tcp/127.0.0.1/$1' _ "$1" >/dev/null 2>&1
}

supabase_ready() {
  local status
  status="$(http_status "$SUPABASE_URL/auth/v1/health")"
  [[ "$status" != "000" && -n "$status" ]]
}

ap_ready() { [[ "$(http_status "$AP_URL/health")" == "200" ]]; }

abo_ready() {
  local status
  status="$(http_status "$ABO_URL/v1/offers" \
    -H 'Host: billing.vendor.test' \
    -H 'Abo-Contract-Version: 1')"
  # A healthy, unauthenticated clinic API answers 401. A 2xx response is also
  # accepted for local setups that add a dev authentication bypass.
  [[ "$status" == "401" || "$status" == "200" ]]
}

viewer_ready() {
  local status
  status="$(http_status "$VIEWER_URL/")"
  [[ "$status" == "200" ]]
}

wait_for_ready() {
  local name="$1" ready_fn="$2" process_id="${3:-}" timeout_seconds="${4:-$START_TIMEOUT}"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if "$ready_fn"; then
      log "$name is ready."
      return 0
    fi
    if [[ -n "$process_id" ]] && ! kill -0 "$process_id" 2>/dev/null; then
      return 2
    fi
    sleep 2
  done
  return 1
}

print_log_tail() {
  local name="$1" file="$2"
  log "$name startup output (last 100 lines):"
  tail -n 100 "$file" >&2 2>/dev/null || true
}

group_has_wrangler() {
  local pgid="$1"
  ps -eo pgid=,args= | awk -v wanted="$pgid" '$1 == wanted && /wrangler dev/ { found = 1 } END { exit !found }'
}

stop_group() {
  local pgid="$1"
  if [[ "$pgid" =~ ^[0-9]+$ ]] && group_has_wrangler "$pgid"; then
    log "Stopping Wrangler process group $pgid."
    kill -TERM -- "-$pgid" 2>/dev/null || true
    for _ in {1..10}; do
      group_has_wrangler "$pgid" || break
      sleep 1
    done
    if group_has_wrangler "$pgid"; then
      kill -KILL -- "-$pgid" 2>/dev/null || true
    fi
  fi
}

stop_owned_workers() {
  local pid_file service pgid
  for service in ai-platform abo viewer; do
    pid_file="$PID_DIR/$service.pgid"
    [[ -f "$pid_file" ]] || continue
    pgid="$(cat "$pid_file")"
    stop_group "$pgid"
    rm -f "$pid_file"
  done
}

local_issuer_keys() {
  local encoded_password database_url issuer_keys
  encoded_password="$(POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}" python3 -c \
    'import os, urllib.parse; print(urllib.parse.quote(os.environ["POSTGRES_PASSWORD"], safe=""))')"
  database_url="postgresql://postgres:$encoded_password@127.0.0.1:${SUPABASE_DB_PORT:-54322}/postgres"
  issuer_keys="$(psql "$database_url" -At -v ON_ERROR_STOP=1 -c \
    "SELECT COALESCE(json_agg(json_build_object('kid', kid, 'public_key', public_key) ORDER BY kid)::text, '[]') FROM ai_internal.issuer_key WHERE status IN ('signing', 'next') AND not_before <= now() AND not_after > now();")"
  unset database_url encoded_password
  [[ -n "$issuer_keys" ]] || fail "Could not load the local AI issuer public keys."
  printf '%s' "$issuer_keys"
}

stop_stack_if_owned() {
  if [[ -f "$STATE_DIR/compose-started-by-script" ]]; then
    log "Stopping the local Supabase Compose stack started by this script."
    (cd "$COMPOSE_DIR" && docker compose down) || true
    rm -f "$STATE_DIR/compose-started-by-script"
  fi
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  local pid
  for pid in "${TAIL_PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${STARTED_PGIDS[@]:-}"; do stop_group "$pid"; done
  for pid in "${STARTED_PGIDS[@]:-}"; do
    rm -f "$PID_DIR/ai-platform.pgid" "$PID_DIR/abo.pgid" "$PID_DIR/viewer.pgid"
  done
  if (( STARTED_SUPABASE == 1 )); then stop_stack_if_owned; fi
  if (( status != 0 )); then log "Startup stopped with exit code $status."; fi
  exit "$status"
}

prepare_dependencies() {
  local dir name executable
  for dir in "$AP_DIR" "$ABO_DIR" "$VIEWER_DIR"; do
    name="$(basename "$dir")"
    if [[ ! -d "$dir/node_modules" ]]; then
      log "Installing $name dependencies with npm ci."
      (cd "$dir" && npm ci)
    fi
  done
}

prepare_supabase_env() {
  local env_file="$COMPOSE_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    cp "$COMPOSE_DIR/.env.example" "$env_file"
    log "Created backend/local/.env from .env.example."
  fi
  # Values are local development settings; never print the sourced file.
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
  SUPABASE_PORT="${SUPABASE_HTTP_PORT:-54321}"
  SUPABASE_URL="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:$SUPABASE_PORT}"
}

load_supabase_env_if_present() {
  local env_file="$COMPOSE_DIR/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    SUPABASE_PORT="${SUPABASE_HTTP_PORT:-54321}"
    SUPABASE_URL="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:$SUPABASE_PORT}"
  fi
}

apply_supabase_migrations() {
  local encoded_password database_url
  encoded_password="$(POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}" python3 -c \
    'import os, urllib.parse; print(urllib.parse.quote(os.environ["POSTGRES_PASSWORD"], safe=""))')"
  database_url="postgresql://postgres:$encoded_password@127.0.0.1:${SUPABASE_DB_PORT:-54322}/postgres"
  log "Applying pending Supabase migrations (no database reset)."
  supabase migration up --db-url "$database_url" --workdir "$BACKEND_DIR"
  unset database_url encoded_password POSTGRES_PASSWORD SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY SUPABASE_JWT_SECRET
}

apply_d1_migrations() {
  mkdir -p "$STATE_DIR/ai-platform" "$STATE_DIR/abo"
  log "Applying pending AI Platform D1 migrations."
  (cd "$AP_DIR" && printf 'y\n' | npx wrangler d1 migrations apply ai-platform-development \
    --local --env development --persist-to "$STATE_DIR/ai-platform")
  log "Applying pending ABO D1 migrations."
  (cd "$ABO_DIR" && printf 'y\n' | npx wrangler d1 migrations apply abo-development \
    --local --env development --persist-to "$STATE_DIR/abo")
}

start_worker() {
  local service="$1" dir="$2" port="$3" state_path="$4" ready_fn="$5" log_file="$6"
  local pid_file="$PID_DIR/$service.pgid" pid issuer_keys=""
  local -a worker_args=(--ip 127.0.0.1 --port "$port" --persist-to "$state_path" --show-interactive-dev-session=false)

  if [[ "$service" == "abo" ]]; then
    issuer_keys="$(local_issuer_keys)"
    worker_args+=(--var "ISSUER_KEYS:$issuer_keys")
  fi

  if "$ready_fn"; then
    log "$service is already running at http://127.0.0.1:$port; reusing it."
    return 0
  fi

  if port_open "$port"; then
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      stop_group "$pid"
      rm -f "$pid_file"
    fi
  fi
  if port_open "$port"; then
    fail "port $port is occupied, but $service did not pass its health check. Stop the process using it or set a different port."
  fi

  mkdir -p "$(dirname "$state_path")" "$PID_DIR" "$LOG_DIR"
  : > "$log_file"
  log "Starting $service on port $port (logs: $log_file)."
  case "$service" in
    ai-platform|abo)
      (cd "$dir" && setsid npm run dev -- "${worker_args[@]}") >"$log_file" 2>&1 &
      ;;
    viewer)
      (cd "$dir" && setsid npm run dev -- --host 127.0.0.1 --port "$port" --strictPort) >"$log_file" 2>&1 &
      ;;
  esac
  pid=$!
  printf '%s\n' "$pid" > "$pid_file"
  STARTED_PGIDS+=("$pid")
  tail -n +1 -F "$log_file" &
  TAIL_PIDS+=("$!")

  if wait_for_ready "$service" "$ready_fn" "$pid"; then
    return 0
  else
    local result=$?
    print_log_tail "$service" "$log_file"
    if (( result == 2 )); then fail "$service exited before it became ready."; fi
    fail "$service did not become ready within ${START_TIMEOUT}s."
  fi
}

start_supabase() {
  local running_containers
  if supabase_ready; then
    log "Supabase is already responding at $SUPABASE_URL; reusing it."
    SUPABASE_WAS_READY=1
    return 0
  fi

  if [[ ! -f "$COMPOSE_DIR/.env" ]]; then prepare_supabase_env; fi
  running_containers="$(cd "$COMPOSE_DIR" && docker compose ps --status running -q | wc -l | tr -d ' ')"
  if [[ "$running_containers" == "0" ]]; then STARTED_SUPABASE=1; fi

  log "Starting the local Supabase Docker Compose stack."
  (cd "$COMPOSE_DIR" && docker compose up -d)
  if (( STARTED_SUPABASE == 1 )); then
    mkdir -p "$STATE_DIR"
    : > "$STATE_DIR/compose-started-by-script"
  fi

  if ! wait_for_ready "Supabase gateway" supabase_ready "" "$START_TIMEOUT"; then
    (cd "$COMPOSE_DIR" && docker compose ps) >&2 || true
    (cd "$COMPOSE_DIR" && docker compose logs --tail=80 kong auth rest) >&2 || true
    fail "Supabase did not become ready within ${START_TIMEOUT}s."
  fi
}

print_service_status() {
  local name="$1" address="$2" url="$3" status="" result
  shift 3
  status="$(http_status "$url" "$@")"
  if [[ "$status" == "200" || ( "$name" == "ABO" && "$status" == "401" ) ]]; then
    result="ready (HTTP $status)"
  else
    result="not ready (HTTP ${status:-000})"
  fi
  printf '  %-14s %-39s %s\n' "$name" "$address" "$result"
}

show_status() {
  printf '%-16s %-39s %s\n' 'SERVICE' 'ADDRESS' 'STATUS'
  print_service_status 'Supabase API' "$SUPABASE_URL" "$SUPABASE_URL/auth/v1/health"
  print_service_status 'Supabase Studio' "http://127.0.0.1:${SUPABASE_STUDIO_PORT:-54323}" \
    "http://127.0.0.1:${SUPABASE_STUDIO_PORT:-54323}"
  print_service_status 'AP' "$AP_URL" "$AP_URL/health"
  print_service_status 'ABO' "$ABO_URL" "$ABO_URL/v1/offers" \
    -H 'Host: billing.vendor.test' -H 'Abo-Contract-Version: 1'
  if (( INCLUDE_VIEWER == 1 )); then
    print_service_status 'AI Viewer' "$VIEWER_URL" "$VIEWER_URL/"
  fi
  if [[ -f "$STATE_DIR/compose-started-by-script" ]]; then
    log "Supabase Compose is marked as started by this script."
  fi
}

stop_command() {
  mkdir -p "$PID_DIR"
  stop_owned_workers
  stop_stack_if_owned
  log "Stopped services owned by the local stack launcher. Services started elsewhere were left alone."
}

start_command() {
  local dir
  require_command curl
  require_command timeout
  require_command setsid
  require_command docker
  require_command supabase
  require_command npm
  require_command npx
  require_command python3
  require_command psql
  require_command ps

  node -e 'const major=Number(process.versions.node.split(".")[0]); if(major < 22) process.exit(1)' \
    || fail "Node.js 22 or newer is required for Wrangler."
  docker compose version >/dev/null 2>&1 || fail "Docker Compose is required."

  mkdir -p "$STATE_DIR" "$LOG_DIR" "$PID_DIR"
  RUN_LOG_DIR="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$RUN_LOG_DIR"

  if [[ ! -f "$COMPOSE_DIR/.env" ]]; then prepare_supabase_env; else
    set -a
    # shellcheck disable=SC1090
    source "$COMPOSE_DIR/.env"
    set +a
    SUPABASE_PORT="${SUPABASE_HTTP_PORT:-54321}"
    SUPABASE_URL="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:$SUPABASE_PORT}"
  fi

  prepare_dependencies
  start_supabase
  apply_supabase_migrations
  apply_d1_migrations

  # Start AP before ABO so Wrangler can connect the ABO service binding locally.
  start_worker ai-platform "$AP_DIR" "$AP_PORT" "$STATE_DIR/ai-platform" ap_ready "$RUN_LOG_DIR/ai-platform.log"
  start_worker abo "$ABO_DIR" "$ABO_PORT" "$STATE_DIR/abo" abo_ready "$RUN_LOG_DIR/abo.log"
  if (( INCLUDE_VIEWER == 1 )); then
    start_worker viewer "$VIEWER_DIR" "$VIEWER_PORT" "$STATE_DIR/viewer" viewer_ready "$RUN_LOG_DIR/viewer.log"
  fi

  log "Non-Flutter development stack is ready:"
  show_status
  log "Press Ctrl-C to stop services started by this run. Logs are under $RUN_LOG_DIR."

  while true; do
    local index pid service
    for index in "${!STARTED_PGIDS[@]}"; do
      pid="${STARTED_PGIDS[$index]}"
      if ! kill -0 "$pid" 2>/dev/null; then
        case "$pid" in
          "$(cat "$PID_DIR/ai-platform.pgid" 2>/dev/null || true)") service=ai-platform ;;
          "$(cat "$PID_DIR/abo.pgid" 2>/dev/null || true)") service=abo ;;
          *) service=viewer ;;
        esac
        print_log_tail "$service" "$RUN_LOG_DIR/$service.log"
        fail "$service stopped unexpectedly."
      fi
    done
    if ! supabase_ready; then fail "Supabase gateway stopped responding."; fi
    sleep 2
  done
}

main() {
  local command="start"
  if (($# > 0)) && [[ "$1" != --* ]]; then command="$1"; shift; fi
  while (($# > 0)); do
    case "$1" in
      --no-viewer) INCLUDE_VIEWER=0 ;;
      -h|--help) usage; return 0 ;;
      *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
  done

  case "$command" in
    start)
      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      start_command
      ;;
    status)
      load_supabase_env_if_present
      show_status
      ;;
    stop)
      stop_command
      ;;
    *) usage >&2; fail "unknown command: $command" ;;
  esac
}

main "$@"
