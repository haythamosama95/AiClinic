#!/usr/bin/env bash
# Reports Riverpod providers under presentation/providers/ with zero references
# elsewhere in frontend/lib. Intended as a CI warning — not a hard gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/lib"
PROVIDERS_DIR="$LIB/features"

if [[ ! -d "$PROVIDERS_DIR" ]]; then
  echo "find_dead_providers: no features directory at $PROVIDERS_DIR" >&2
  exit 1
fi

found=0

while IFS= read -r file; do
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue

    # Skip generated/local declarations inside the defining file.
    hits=$(rg -n --glob '*.dart' "\\b$name\\b" "$LIB" 2>/dev/null | rg -v ":.*\\b(final|class|typedef|enum|abstract|extension)\\b.*\\b$name\\b" || true)
    count=$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
      echo "WARN: possible dead provider '$name' in ${file#$ROOT/}"
      found=$((found + 1))
    fi
  done < <(rg -o --no-line-number '(?<=final )[A-Za-z_][A-Za-z0-9_]*Provider' "$file" 2>/dev/null | sort -u)
done < <(find "$PROVIDERS_DIR" -path '*/presentation/providers/*.dart' -type f | sort)

if [[ "$found" -eq 0 ]]; then
  echo "find_dead_providers: no zero-reference providers detected"
fi

exit 0
