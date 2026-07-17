#!/usr/bin/env bash
# Start the AI Gateway locally (serves the control-plane dashboard at /dashboard).
# Usage: ./scripts/start_dev.sh   (from ai/gateway, or any cwd)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
LOCAL_ENV="${REPO_ROOT}/backend/local/.env"

PORT="${GATEWAY_PORT:-8090}"

# Load clinic Supabase settings when available.
if [[ -f "${LOCAL_ENV}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${LOCAL_ENV}" && set +a
fi

# Prefer clinic Supabase JWT secret so dashboard sign-in tokens validate.
GATEWAY_JWT_SECRET="${GATEWAY_JWT_SECRET:-${SUPABASE_JWT_SECRET:-dev-secret}}"
JWT_SECRET="${GATEWAY_JWT_SECRET}"

_supabase_jwks_ok() {
  local base="$1"
  curl -sf "${base}/auth/v1/.well-known/jwks.json" 2>/dev/null | grep -q '"keys"'
}

_resolve_supabase_url() {
  local candidate
  for candidate in \
    "${GATEWAY_SUPABASE_URL:-}" \
    "${SUPABASE_PUBLIC_URL:-}" \
    "http://127.0.0.1:54321" \
    "http://127.0.0.1:55321"; do
    [[ -n "${candidate}" ]] || continue
    if _supabase_jwks_ok "${candidate}"; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

if [[ -z "${GATEWAY_SUPABASE_URL:-}" ]]; then
  if resolved="$(_resolve_supabase_url)"; then
    export GATEWAY_SUPABASE_URL="${resolved}"
    export GATEWAY_JWKS_URL="${GATEWAY_JWKS_URL:-${resolved}/auth/v1/.well-known/jwks.json}"
    if [[ "${resolved}" != "${SUPABASE_PUBLIC_URL:-}" ]]; then
      echo "note: using Supabase at ${resolved} (auth/JWKS probe; override with GATEWAY_SUPABASE_URL)" >&2
    fi
  fi
fi

if [[ -z "${GATEWAY_SUPABASE_ANON_KEY:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  export GATEWAY_SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"
fi

if [[ -z "${GATEWAY_JWKS_URL:-}" && -n "${GATEWAY_SUPABASE_URL:-}" ]]; then
  export GATEWAY_JWKS_URL="${GATEWAY_SUPABASE_URL}/auth/v1/.well-known/jwks.json"
fi

if command -v ss >/dev/null 2>&1 && ss -tlnH "sport = :${PORT}" 2>/dev/null | grep -q .; then
  echo "error: port ${PORT} is already in use." >&2
  ss -tlnpH "sport = :${PORT}" 2>/dev/null || true
  echo >&2
  echo "Stop the existing gateway (Ctrl+C in its terminal), or use another port:" >&2
  echo "  GATEWAY_PORT=8091 ./scripts/start_dev.sh" >&2
  exit 1
fi

if [[ ! -x "$ROOT/.venv/bin/uvicorn" ]]; then
  echo "error: gateway venv not found. First-time setup:" >&2
  echo "  cd $ROOT" >&2
  echo "  python3.13 -m venv .venv   # requires Python >= 3.12" >&2
  echo "  .venv/bin/pip install -r requirements-dev.lock.txt" >&2
  echo "  .venv/bin/pip install -e . --no-deps" >&2
  exit 1
fi

echo "==> AI Gateway on http://localhost:${PORT}"
echo "    Dashboard: http://localhost:${PORT}/dashboard"
if [[ -n "${GATEWAY_SUPABASE_URL:-}" ]]; then
  echo "    Supabase:  ${GATEWAY_SUPABASE_URL} (dashboard sign-in)"
fi
echo "    Press Ctrl+C to stop"
echo

export GATEWAY_JWT_SECRET="$JWT_SECRET"
exec "$ROOT/.venv/bin/uvicorn" gateway.main:create_app --factory --host 0.0.0.0 --port "$PORT"
