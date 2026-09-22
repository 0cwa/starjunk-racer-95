#!/usr/bin/env bash
set -euo pipefail

DUMP_DIR="${1:-build/webgpu-spv}"
OUTPUT_DIR="${2:-build/webgpu-spv-analysis}"

if ! command -v spirv-val >/dev/null 2>&1; then
  echo "spirv-val is required (install the spirv-tools package)" >&2
  exit 2
fi
if ! command -v spirv-dis >/dev/null 2>&1; then
  echo "spirv-dis is required (install the spirv-tools package)" >&2
  exit 2
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
files=("$DUMP_DIR"/*.spv)
if (( ${#files[@]} == 0 )); then
  echo "No SPIR-V dumps found under $DUMP_DIR"
  printf 'no dumps\n' > "$OUTPUT_DIR/summary.txt"
  exit 0
fi

status=0
: > "$OUTPUT_DIR/summary.txt"
for file in "${files[@]}"; do
  base="$(basename "$file" .spv)"
  validation="$OUTPUT_DIR/$base.val.txt"
  disassembly="$OUTPUT_DIR/$base.spvasm"

  set +e
  spirv-val --target-env spv1.3 "$file" >"$validation" 2>&1
  validation_rc=$?
  set -e

  if (( validation_rc == 0 )); then
    printf '%s VALID spv1.3\n' "$base" | tee -a "$OUTPUT_DIR/summary.txt"
  else
    printf '%s INVALID spv1.3 rc=%d\n' "$base" "$validation_rc" | tee -a "$OUTPUT_DIR/summary.txt"
    status=1
  fi

  if ! spirv-dis --raw-id "$file" -o "$disassembly"; then
    printf '%s DISASSEMBLY_FAILED\n' "$base" | tee -a "$OUTPUT_DIR/summary.txt"
    status=1
  fi
done

# This tool reports validation status through the summary/artifacts. The browser
# correctness gate remains the authority for CI pass/fail so a diagnostic
# validator mismatch cannot accidentally weaken or replace renderer validation.
exit 0
