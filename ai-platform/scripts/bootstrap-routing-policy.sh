#!/usr/bin/env bash
#
# Publish and promote the platform-default routing policy so invoke can route.
# Idempotent: safe to re-run after migrations or on a fresh local D1/R2.
#
# Prerequisites:
#   - Worker reachable at GATEWAY (default http://127.0.0.1:8787)
#   - OPERATOR_BEARER_TOKEN (env, or ai-platform/.dev.vars[.development])
#   - D1 migrations applied for the target env
#
# Usage:
#   ./scripts/bootstrap-routing-policy.sh
#   ./scripts/bootstrap-routing-policy.sh --env staging --remote --gateway https://…

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
platform_dir="$(cd "${script_dir}/.." && pwd)"

wrangler_env="development"
d1_target=(--local)
gateway="${GATEWAY:-http://127.0.0.1:8787}"
fixture_rel="control/routing-policy/platform-default/1.json"

usage() {
  cat <<'EOF'
Bootstrap the default routing policy (publish + promote platform-default/1.json).

Usage:
  ./scripts/bootstrap-routing-policy.sh [options]

Options:
  --env NAME       Wrangler env: development | staging | production (default: development)
  --local          Query local D1 (default for development)
  --remote         Query remote D1 (required for deployed Workers)
  --gateway URL    Worker base URL (default: http://127.0.0.1:8787 or $GATEWAY)
  --fixture PATH   Policy document relative to ai-platform/ (default: platform-default/1.json)
  -h, --help       Show this help

Environment:
  OPERATOR_BEARER_TOKEN   Operator secret (or set in .dev.vars / .dev.vars.<env>)
  GATEWAY                 Default Worker URL when --gateway is omitted

Typical local bring-up (Worker already running via npm run dev):
  cd ai-platform
  npx wrangler d1 migrations apply ai-platform-development --local --env development
  npm run bootstrap:routing-policy
EOF
}

while (($# > 0)); do
  case "$1" in
    --env)
      wrangler_env="${2:?--env requires a value}"
      shift 2
      ;;
    --local)
      d1_target=(--local)
      shift
      ;;
    --remote)
      d1_target=(--remote)
      shift
      ;;
    --gateway)
      gateway="${2:?--gateway requires a value}"
      shift 2
      ;;
    --fixture)
      fixture_rel="${2:?--fixture requires a value}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_command curl
require_command python3
require_command npx

cd "${platform_dir}"

fixture_path="${platform_dir}/${fixture_rel}"
if [[ ! -f "${fixture_path}" ]]; then
  printf 'ERROR: fixture not found: %s\n' "${fixture_path}" >&2
  exit 1
fi

read -r policy_id policy_version <<<"$(python3 - <<PY
import json
with open("${fixture_path}") as f:
    doc = json.load(f)
print(doc["policy_id"], doc["policy_version"])
PY
)"

if [[ -z "${OPERATOR_BEARER_TOKEN:-}" ]]; then
  for vars_file in ".dev.vars.${wrangler_env}" ".dev.vars"; do
    if [[ -f "${vars_file}" ]]; then
      token_line="$(grep -E '^OPERATOR_BEARER_TOKEN=' "${vars_file}" | head -1 || true)"
      if [[ -n "${token_line}" ]]; then
        OPERATOR_BEARER_TOKEN="${token_line#OPERATOR_BEARER_TOKEN=}"
        OPERATOR_BEARER_TOKEN="${OPERATOR_BEARER_TOKEN#\"}"
        OPERATOR_BEARER_TOKEN="${OPERATOR_BEARER_TOKEN%\"}"
        export OPERATOR_BEARER_TOKEN
        break
      fi
    fi
  done
fi

if [[ -z "${OPERATOR_BEARER_TOKEN:-}" ]]; then
  printf 'ERROR: OPERATOR_BEARER_TOKEN is not set (env or .dev.vars)\n' >&2
  exit 1
fi

d1_database="ai-platform-${wrangler_env}"

health_code="$(curl -sS -o /dev/null -w '%{http_code}' "${gateway}/health" || true)"
if [[ "${health_code}" != "200" ]]; then
  printf 'ERROR: Worker health check failed (%s/health → HTTP %s)\n' "${gateway}" "${health_code}" >&2
  printf 'Start the gateway first (npm run dev) or pass --gateway for a deployed Worker.\n' >&2
  exit 1
fi

d1_json="$(npx wrangler d1 execute "${d1_database}" "${d1_target[@]}" --env "${wrangler_env}" \
  --command "SELECT version, status FROM routing_policy WHERE policy_id = '${policy_id}' ORDER BY active_from DESC, rowid DESC;" \
  --json)"

read -r target_status active_version <<<"$(D1_JSON="${d1_json}" POLICY_ID="${policy_id}" TARGET_VERSION="${policy_version}" python3 - <<'PY'
import json, os, sys

payload = json.loads(os.environ["D1_JSON"])
rows = (payload[0].get("results") or []) if payload else []
policy_id = os.environ["POLICY_ID"]
target_version = str(os.environ["TARGET_VERSION"])

target_status = ""
active_version = ""
for row in rows:
    version = str(row.get("version", ""))
    status = str(row.get("status", ""))
    if version == target_version and not target_status:
        target_status = status
    if status == "active" and not active_version:
        active_version = version

print(target_status, active_version)
PY
)"

if [[ "${active_version}" == "${policy_version}" ]]; then
  printf 'routing policy %s@%s is already active — nothing to do\n' "${policy_id}" "${policy_version}"
  exit 0
fi

if [[ -n "${active_version}" && "${active_version}" != "${policy_version}" ]]; then
  printf 'routing policy %s@%s is active — skipping bootstrap of v%s\n' \
    "${policy_id}" "${active_version}" "${policy_version}"
  exit 0
fi

operator_post() {
  local url="$1"
  local body="${2:-}"
  local tmp
  tmp="$(mktemp)"
  local code
  if [[ -n "${body}" ]]; then
    code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "${url}" \
      -H "Authorization: Bearer ${OPERATOR_BEARER_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${body}")"
  else
    code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "${url}" \
      -H "Authorization: Bearer ${OPERATOR_BEARER_TOKEN}")"
  fi
  if [[ "${code}" != "200" ]]; then
    printf 'ERROR: POST %s → HTTP %s\n' "${url}" "${code}" >&2
    cat "${tmp}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  if [[ -s "${tmp}" ]]; then
    cat "${tmp}"
    printf '\n'
  fi
  rm -f "${tmp}"
}

if [[ -z "${target_status}" ]]; then
  printf 'publishing %s@%s from %s\n' "${policy_id}" "${policy_version}" "${fixture_rel}"
  publish_body="$(python3 - <<PY
import json
with open("${fixture_path}") as f:
    doc = json.load(f)
print(json.dumps({"document": doc}))
PY
)"
  publish_tmp="$(mktemp)"
  publish_code="$(curl -sS -o "${publish_tmp}" -w '%{http_code}' -X POST \
    "${gateway}/control/routing-policies/publish" \
    -H "Authorization: Bearer ${OPERATOR_BEARER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${publish_body}")"
  if [[ "${publish_code}" == "409" ]]; then
    printf 'publish: already published (%s@%s)\n' "${policy_id}" "${policy_version}"
  elif [[ "${publish_code}" != "200" ]]; then
    printf 'ERROR: publish → HTTP %s\n' "${publish_code}" >&2
    cat "${publish_tmp}" >&2
    rm -f "${publish_tmp}"
    exit 1
  else
    if [[ -s "${publish_tmp}" ]]; then
      cat "${publish_tmp}"
      printf '\n'
    fi
    printf 'published %s@%s\n' "${policy_id}" "${policy_version}"
  fi
  rm -f "${publish_tmp}"
elif [[ "${target_status}" == "published" || "${target_status}" == "canary" ]]; then
  printf 'found %s@%s with status=%s — promote only\n' "${policy_id}" "${policy_version}" "${target_status}"
else
  printf 'ERROR: unexpected status %s for %s@%s\n' "${target_status}" "${policy_id}" "${policy_version}" >&2
  exit 1
fi

printf 'promoting %s@%s to active\n' "${policy_id}" "${policy_version}"
operator_post "${gateway}/control/routing-policies/${policy_id}/versions/${policy_version}/promote"

printf 'done — %s@%s is active (restart npm run dev or wait for config-cache TTL if invoke still misses)\n' \
  "${policy_id}" "${policy_version}"
