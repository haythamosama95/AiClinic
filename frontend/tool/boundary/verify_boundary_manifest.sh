#!/usr/bin/env bash
# Ensures every manifest row with owner=boundary has a matching ManifestScenario in test/boundary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/test/boundary/boundary_coverage_manifest.md"
BOUNDARY_DIR="$ROOT/test/boundary"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Missing manifest at $MANIFEST" >&2
  exit 1
fi

mapfile -t REQUIRED < <(grep '| boundary |' "$MANIFEST" | awk -F'|' '{gsub(/ /,"",$2); print $2}')

MISSING=0
for id in "${REQUIRED[@]}"; do
  if [[ -z "$id" ]]; then
    continue
  fi
  if grep -rq "ManifestScenario('$id')" "$BOUNDARY_DIR" || grep -rq "ManifestScenario(\"$id\")" "$BOUNDARY_DIR"; then
    continue
  fi
  # Role matrix tests use interpolation: ManifestScenario('patientRole.${role.wireValue}.search')
  if [[ "$id" =~ ^patientRole\.([a-z_]+)\.([a-zA-Z]+)$ ]]; then
    role="${BASH_REMATCH[1]}"
    op="${BASH_REMATCH[2]}"
    if grep -rq "patientRole\.\${role\.wireValue}\.$op" "$BOUNDARY_DIR" || grep -rq "patientRole.\${role.wireValue}.$op" "$BOUNDARY_DIR"; then
      continue
    fi
  fi
  if [[ "$id" =~ ^permission\.loadGrantedPermissions\.([a-z_]+)$ ]]; then
    role="${BASH_REMATCH[1]}"
    if grep -rq "permission.loadGrantedPermissions.\${role.wireValue}" "$BOUNDARY_DIR"; then
      continue
    fi
  fi
  if [[ "$id" =~ ^provisioning\.createStaffAccount\.perRole\.([a-z_]+)$ ]]; then
    role="${BASH_REMATCH[1]}"
    if grep -rq "provisioning.createStaffAccount.perRole.\${role.wireValue}" "$BOUNDARY_DIR" \
      || grep -rq "provisioning.createStaffAccount.perRole.$role" "$BOUNDARY_DIR"; then
      continue
    fi
  fi
  echo "MISSING boundary test for scenario: $id" >&2
  MISSING=$((MISSING + 1))
done

if [[ "$MISSING" -gt 0 ]]; then
  echo "FAIL: $MISSING manifest scenario(s) without tests." >&2
  exit 1
fi

echo "OK: All ${#REQUIRED[@]} boundary manifest scenarios are referenced in tests."
