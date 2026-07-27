#!/usr/bin/env bash
# Shared verbose logging for runner shell entry points.
# Source from other scripts: . "$(dirname "${BASH_SOURCE[0]}")/_verbose_log.sh"

export AI_VERBOSE_LOG_SOURCE="${AI_VERBOSE_LOG_SOURCE:-runner}"
_VERBOSE_CLI_SET=0
_LOG_TARGET_CLI_SET=0
_VERBOSE_LOG_FILE_CLI_SET=0
_VERBOSE_SHIFT=0
_VERBOSE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AI_COMMON_SRC="$(cd "${_VERBOSE_SCRIPT_DIR}/../../common/src" && pwd)"
export PYTHONPATH="${_AI_COMMON_SRC}${PYTHONPATH:+:${PYTHONPATH}}"

_runner_validate_verbose_level() {
  local level="$1"
  if [[ "${level}" =~ ^[0-2]$ ]]; then
    echo "${level}"
    return 0
  fi
  echo "error: verbosity level must be 0, 1, or 2 (got: ${level})" >&2
  return 1
}

_runner_apply_verbose_level() {
  local level
  level="$(_runner_validate_verbose_level "$1")" || return 1
  export AI_VERBOSE_LOG_LEVEL="${level}"
  _VERBOSE_CLI_SET=1
}

# Returns 0 when consumed, 1 when not a verbose option, 2 on validation error.
_runner_try_verbose_option() {
  _VERBOSE_SHIFT=0
  case "$1" in
    -v)
      if [[ $# -lt 2 ]]; then
        echo "error: -v requires a level (0, 1, or 2)" >&2
        return 2
      fi
      _runner_apply_verbose_level "$2" || return 2
      _VERBOSE_SHIFT=2
      return 0
      ;;
    -v[0-2])
      _runner_apply_verbose_level "${1#-v}" || return 2
      _VERBOSE_SHIFT=1
      return 0
      ;;
    --verbose)
      if [[ $# -lt 2 ]]; then
        echo "error: --verbose requires a level (0, 1, or 2)" >&2
        return 2
      fi
      _runner_apply_verbose_level "$2" || return 2
      _VERBOSE_SHIFT=2
      return 0
      ;;
    --verbose=[0-2])
      _runner_apply_verbose_level "${1#--verbose=}" || return 2
      _VERBOSE_SHIFT=1
      return 0
      ;;
    [0-2])
      _runner_apply_verbose_level "$1" || return 2
      _VERBOSE_SHIFT=1
      return 0
      ;;
  esac
  return 1
}

# After CLI parsing: keep CLI value, else normalize AI_VERBOSE_LOG_LEVEL from the environment.
_runner_finalize_verbose_level() {
  if [[ "${_VERBOSE_CLI_SET}" -eq 0 ]]; then
    export AI_VERBOSE_LOG_LEVEL="$(_runner_verbose_level)"
  fi
}

_runner_validate_log_target() {
  local target="$1"
  case "${target}" in
    console | file | both)
      echo "${target}"
      return 0
      ;;
  esac
  echo "error: log target must be console, file, or both (got: ${target})" >&2
  return 1
}

_runner_apply_log_target() {
  local target
  target="$(_runner_validate_log_target "$1")" || return 1
  export AI_VERBOSE_LOG_TARGET="${target}"
  _LOG_TARGET_CLI_SET=1
}

_runner_apply_log_file() {
  export AI_VERBOSE_LOG_FILE="$1"
  _VERBOSE_LOG_FILE_CLI_SET=1
}

# Returns 0 when consumed, 1 when not a log-target option, 2 on validation error.
_runner_try_log_target_option() {
  _VERBOSE_SHIFT=0
  case "$1" in
    -l)
      if [[ $# -lt 2 ]]; then
        echo "error: -l requires a target (console, file, or both)" >&2
        return 2
      fi
      _runner_apply_log_target "$2" || return 2
      _VERBOSE_SHIFT=2
      return 0
      ;;
    -lconsole | -lfile | -lboth)
      _runner_apply_log_target "${1#-l}" || return 2
      _VERBOSE_SHIFT=1
      return 0
      ;;
    --log-target)
      if [[ $# -lt 2 ]]; then
        echo "error: --log-target requires a value (console, file, or both)" >&2
        return 2
      fi
      _runner_apply_log_target "$2" || return 2
      _VERBOSE_SHIFT=2
      return 0
      ;;
    --log-target=console | --log-target=file | --log-target=both)
      _runner_apply_log_target "${1#--log-target=}" || return 2
      _VERBOSE_SHIFT=1
      return 0
      ;;
    --log-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --log-file requires a path" >&2
        return 2
      fi
      _runner_apply_log_file "$2"
      _VERBOSE_SHIFT=2
      return 0
      ;;
    --log-file=*)
      _runner_apply_log_file "${1#--log-file=}"
      _VERBOSE_SHIFT=1
      return 0
      ;;
  esac
  return 1
}

_runner_verbose_log_target() {
  local raw="${AI_VERBOSE_LOG_TARGET:-console}"
  case "${raw}" in
    console | file | both) echo "${raw}" ;;
    *) echo console ;;
  esac
}

_runner_verbose_log_dir() {
  if [[ -n "${RUNNER_LOG_DIR:-}" ]]; then
    echo "${RUNNER_LOG_DIR}"
    return 0
  fi
  if [[ -n "${GATEWAY_LOG_DIR:-}" ]]; then
    echo "${GATEWAY_LOG_DIR}"
    return 0
  fi
  if [[ -n "${_VERBOSE_LOG_ROOT:-}" ]]; then
    echo "${_VERBOSE_LOG_ROOT}/logs"
    return 0
  fi
  echo "ai/logs"
}

# Create a timestamped verbose log for this start-script run and point
# verbose.log at it via symlink.
_runner_allocate_verbose_log_file() {
  local log_dir timestamp base_name run_file link_path
  log_dir="$(_runner_verbose_log_dir)"
  mkdir -p "${log_dir}"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  base_name="verbose-${timestamp}.log"
  run_file="${log_dir}/${base_name}"
  link_path="${log_dir}/verbose.log"
  : > "${run_file}"
  ln -sfn "${base_name}" "${link_path}"
  echo "${run_file}"
}

_runner_default_verbose_log_file() {
  if [[ -n "${AI_VERBOSE_LOG_FILE:-}" ]]; then
    echo "${AI_VERBOSE_LOG_FILE}"
    return 0
  fi
  if [[ -n "${RUNNER_LOG_DIR:-}" ]]; then
    echo "${RUNNER_LOG_DIR}/verbose.log"
    return 0
  fi
  if [[ -n "${GATEWAY_LOG_DIR:-}" ]]; then
    echo "${GATEWAY_LOG_DIR}/verbose.log"
    return 0
  fi
  if [[ -n "${_VERBOSE_LOG_ROOT:-}" ]]; then
    echo "${_VERBOSE_LOG_ROOT}/logs/verbose.log"
    return 0
  fi
  echo "ai/logs/verbose.log"
}

# After CLI parsing: normalize target and ensure default file path when needed.
_runner_finalize_log_target() {
  if [[ "${_LOG_TARGET_CLI_SET}" -eq 0 ]]; then
    export AI_VERBOSE_LOG_TARGET="$(_runner_verbose_log_target)"
  fi
  local target="${AI_VERBOSE_LOG_TARGET}"
  if [[ "${target}" == "file" || "${target}" == "both" ]]; then
    if [[ "${_VERBOSE_LOG_FILE_CLI_SET}" -eq 0 && -z "${AI_VERBOSE_LOG_FILE:-}" ]]; then
      export AI_VERBOSE_LOG_FILE="$(_runner_allocate_verbose_log_file)"
    else
      if [[ -z "${AI_VERBOSE_LOG_FILE:-}" ]]; then
        export AI_VERBOSE_LOG_FILE="$(_runner_default_verbose_log_file)"
      fi
      mkdir -p "$(dirname "${AI_VERBOSE_LOG_FILE}")"
    fi
  fi
}

_runner_verbose_level() {
  local raw="${AI_VERBOSE_LOG_LEVEL:-0}"
  if [[ "${raw}" =~ ^[0-2]$ ]]; then
    echo "${raw}"
  else
    echo 0
  fi
}

_runner_log_json() {
  local min_level="$1"
  local event="$2"
  shift 2
  python3 - "${min_level}" "${event}" "${RUNNER_LOG_NAME:-shell}" "$@" <<'PY'
import sys

from ai_common.verbose_logging import emit_shell_verbose_log

min_level = int(sys.argv[1])
event = sys.argv[2]
component = sys.argv[3]
fields: dict[str, str] = {}
for arg in sys.argv[4:]:
    if "=" not in arg:
        continue
    key, value = arg.split("=", 1)
    fields[key] = value

emit_shell_verbose_log(min_level, event, component=component, **fields)
PY
}

_runner_log_v0() { _runner_log_json 0 "$@"; }
_runner_log_v1() { _runner_log_json 1 "$@"; }
_runner_log_v2() { _runner_log_json 2 "$@"; }

_runner_job_start() {
  local message="$1"
  shift
  _runner_log_v0 "${message}" "runner=${RUNNER_LOG_NAME:-shell}" "$@"
  date +%s%N
}

_runner_job_end() {
  local message="$1"
  local started_ns="$2"
  local success="$3"
  shift 3
  local ended_ns duration_ms
  ended_ns="$(date +%s%N)"
  duration_ms=$(( (ended_ns - started_ns) / 1000000 ))
  _runner_log_v0 "${message}" "runner=${RUNNER_LOG_NAME:-shell}" "success=${success}" "duration_ms=${duration_ms}" "$@"
  if (( $(_runner_verbose_level) >= 1 )); then
    _runner_log_v1 "Operation finished" "duration_ms=${duration_ms}" "success=${success}"
  fi
}
