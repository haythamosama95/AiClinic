#!/usr/bin/env bash
# Copy an existing host Ollama model store into the Docker named volume (no re-download).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/ollama/docker-compose.yaml"
SOURCE="${OLLAMA_HOST_MODELS:-/usr/share/ollama/.ollama}"

usage() {
  cat <<EOF
Usage: import_host_models.sh [source_dir]

Copy blobs + manifests from a host Ollama store into the runner's Docker volume.

Default source: ${SOURCE}

Environment:
  OLLAMA_HOST_MODELS   Override the host model store path

Example:
  ./scripts/import_host_models.sh
  OLLAMA_HOST_MODELS=/usr/share/ollama/.ollama ./scripts/import_host_models.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  SOURCE="$1"
fi

if [[ ! -d "${SOURCE}/models" ]]; then
  echo "error: no Ollama model store at ${SOURCE}/models" >&2
  exit 1
fi

echo "==> Source: ${SOURCE} ($(du -sh "${SOURCE}" | cut -f1))"
echo "==> Ensuring Docker Ollama is up (named volume mode)"
docker compose -f "${COMPOSE_FILE}" up -d

echo "==> Copying model store into /root/.ollama (no download)"
tar -C "${SOURCE}" -cf - . | docker compose -f "${COMPOSE_FILE}" exec -T ollama tar -C /root/.ollama -xf -

echo "==> Models in runner:"
docker compose -f "${COMPOSE_FILE}" exec -T ollama ollama list
