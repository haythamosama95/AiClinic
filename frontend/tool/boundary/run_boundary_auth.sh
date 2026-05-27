#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/tool/run_boundary_tests.py" auth
