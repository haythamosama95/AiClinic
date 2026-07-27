#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_verbose_log.sh
. "${ROOT}/scripts/_verbose_log.sh"
_VERBOSE_LOG_ROOT="${ROOT}"
RUNNER_LOG_NAME="start"

usage() {
  cat <<'EOF'
Usage: ./start.sh [options] [level]

Start the Ollama model runner (Docker Compose).

Options:
  -v, --verbose LEVEL   Verbose logging level 0-2
  -l, --log-target DEST Verbose log destination: console, file, or both (default: console)
  --log-file PATH       Verbose log file path (for file/both targets)
  -h, --help            Show this help

A numeric level (0, 1, or 2) may be passed as a positional argument.

Environment:
  AI_VERBOSE_LOG_LEVEL  Log verbosity: 0, 1, or 2 (default: 0)
  AI_VERBOSE_LOG_TARGET Verbose log destination: console, file, or both (default: console)
  AI_VERBOSE_LOG_FILE   Verbose log file path (default: ai/runners/logs/verbose-YYYYMMDD-HHMMSS.log;
                        verbose.log symlinks to the latest run)
EOF
}

while [[ $# -gt 0 ]]; do
  verbose_rc=1
  _runner_try_verbose_option "$@" && verbose_rc=0 || verbose_rc=$?
  case "${verbose_rc}" in
    0) shift "${_VERBOSE_SHIFT}"; continue ;;
    2) exit 1 ;;
  esac
  log_target_rc=1
  _runner_try_log_target_option "$@" && log_target_rc=0 || log_target_rc=$?
  case "${log_target_rc}" in
    0) shift "${_VERBOSE_SHIFT}"; continue ;;
    2) exit 1 ;;
  esac
  case "$1" in
    -h | --help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

_runner_finalize_verbose_level
_runner_finalize_log_target

started="$(_runner_job_start "Starting Ollama model runner")"
bash "${ROOT}/scripts/ollama_compose.sh" up
_runner_job_end "Ollama model runner is up" "${started}" true
