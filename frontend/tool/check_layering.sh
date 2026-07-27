#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN_DIR="$ROOT/lib/features/visits/domain"

if [[ ! -d "$DOMAIN_DIR" ]]; then
  echo "check_layering: visits domain directory not found at $DOMAIN_DIR" >&2
  exit 1
fi

violations=0

while IFS= read -r -d '' file; do
  while IFS= read -r line; do
    if [[ "$line" =~ ^import[[:space:]]+\'package:ai_clinic/features/[^/]+/presentation/ ]] ||
       [[ "$line" =~ ^import[[:space:]]+\'package:ai_clinic/features/[^/]+/data/ ]] ||
       [[ "$line" =~ ^import[[:space:]]+\'package:ai_clinic/core/ui/ ]] ||
       [[ "$line" == "import 'package:flutter/material.dart';" ]] ||
       [[ "$line" == "import 'package:flutter_quill/flutter_quill.dart';" ]]; then
      echo "${file#"$ROOT/"}: $line" >&2
      violations=$((violations + 1))
    fi
  done < <(grep -E "^import '" "$file" || true)
done < <(find "$DOMAIN_DIR" -maxdepth 1 -name '*.dart' -type f -print0)

if [[ "$violations" -gt 0 ]]; then
  echo "check_layering: found $violations forbidden domain import(s)" >&2
  exit 1
fi

echo "check_layering: no forbidden domain imports"
