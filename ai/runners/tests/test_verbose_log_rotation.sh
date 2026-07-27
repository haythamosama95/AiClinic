#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/_verbose_log.sh
. "${ROOT}/scripts/_verbose_log.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

export RUNNER_LOG_DIR="${tmpdir}/logs"
export AI_VERBOSE_LOG_TARGET=file
unset AI_VERBOSE_LOG_FILE

_runner_finalize_log_target
first="${AI_VERBOSE_LOG_FILE}"
link="${RUNNER_LOG_DIR}/verbose.log"

[[ -f "${first}" ]] || { echo "missing run log: ${first}" >&2; exit 1; }
[[ -L "${link}" ]] || { echo "verbose.log is not a symlink" >&2; exit 1; }
[[ "$(readlink "${link}")" == "$(basename "${first}")" ]] || {
  echo "symlink target mismatch: $(readlink "${link}") vs $(basename "${first}")" >&2
  exit 1
}

sleep 1
unset AI_VERBOSE_LOG_FILE
_runner_finalize_log_target
second="${AI_VERBOSE_LOG_FILE}"

[[ "${second}" != "${first}" ]] || { echo "second run reused first log file" >&2; exit 1; }
[[ "$(readlink "${link}")" == "$(basename "${second}")" ]] || {
  echo "symlink did not move to latest run" >&2
  exit 1
}

echo "verbose log rotation ok"
