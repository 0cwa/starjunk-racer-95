#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/engine/source-lock.json"
GODOT_SOURCE="${1:-$ROOT/build/webgpu-port-candidate/godot}"
WORK_ROOT="${2:-$ROOT/build/webgpu-rust-deps}"
TARGET_ROOT="${STARJUNK_CARGO_TARGET_ROOT:-$WORK_ROOT/cargo-target}"

if [[ ! -f "$GODOT_SOURCE/SConstruct" ]]; then
  echo "Godot candidate source not found: $GODOT_SOURCE" >&2
  exit 2
fi

readarray -t VALUES < <(python3 - "$LOCK" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
deps = lock["webgpu_rust_dependencies"]
print(deps["naga_native"]["repository"])
print(deps["naga_native"]["commit"])
print(deps["spirv_webgpu_transform"]["repository"])
print(deps["spirv_webgpu_transform"]["commit"])
patches = deps["spirv_webgpu_transform"].get("patches", [])
if not patches:
    raise SystemExit("spirv_webgpu_transform must declare reviewed local patches")
for patch in patches:
    print(patch)
PY
)

NAGA_REPO="${VALUES[0]}"
NAGA_SHA="${VALUES[1]}"
SPIRV_REPO="${VALUES[2]}"
SPIRV_SHA="${VALUES[3]}"
SPIRV_PATCH_RELS=("${VALUES[@]:4}")

# The Godot bridge deliberately carries TAG files instead of the archives.
# Refuse to build if its declared dependency identity differs from our lock.
test "$(tr -d '\r\n' < "$GODOT_SOURCE/thirdparty/naga-native/TAG")" = "$NAGA_SHA"
test "$(tr -d '\r\n' < "$GODOT_SOURCE/thirdparty/spirv-webgpu-transform/TAG")" = "$SPIRV_SHA"

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT" "$TARGET_ROOT"

clone_at() {
  local repo="$1"
  local sha="$2"
  local dest="$3"
  git clone --filter=blob:none --no-checkout "$repo" "$dest"
  git -C "$dest" fetch --filter=blob:none origin "$sha"
  git -C "$dest" checkout --detach "$sha"
  test "$(git -C "$dest" rev-parse HEAD)" = "$sha"
}

clone_at "$NAGA_REPO" "$NAGA_SHA" "$WORK_ROOT/naga-native"
clone_at "$SPIRV_REPO" "$SPIRV_SHA" "$WORK_ROOT/spirv-webgpu-transform"

# Keep the upstream transform revision pinned, but apply the ordered reviewed
# local compatibility patch series before building. Dependency identity and
# Starjunk corrections remain separately auditable in source-lock.json.
for patch_rel in "${SPIRV_PATCH_RELS[@]}"; do
  patch_path="$ROOT/$patch_rel"
  test -s "$patch_path"
  git -C "$WORK_ROOT/spirv-webgpu-transform" apply --check "$patch_path"
  git -C "$WORK_ROOT/spirv-webgpu-transform" apply "$patch_path"
done
grep -Fq 'pub const SPV_INSTRUCTION_OP_NOP: u16 = 0;' \
  "$WORK_ROOT/spirv-webgpu-transform/src/spv.rs"
grep -Fq 'An opaque binding-array element may be passed directly to a helper' \
  "$WORK_ROOT/spirv-webgpu-transform/src/splitbindingarray.rs"

rustup target add wasm32-unknown-emscripten

# naga-native generates Rust FFI bindings from its C header during the build.
# Bindgen otherwise discovers the host's /usr/include even though rustc targets
# Emscripten. Force Clang to use the same target/sysroot as emcc.
if [[ -n "${EM_CACHE:-}" ]]; then
  EMSCRIPTEN_SYSROOT="$EM_CACHE/sysroot"
else
  EMSCRIPTEN_SYSROOT="${EMSDK:?EMSDK must be set by the Emscripten environment}/upstream/emscripten/cache/sysroot"
fi
test -d "$EMSCRIPTEN_SYSROOT"
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="--target=wasm32-unknown-emscripten --sysroot=$EMSCRIPTEN_SYSROOT"
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten_unknown="${BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten}"
export CC_wasm32_unknown_emscripten=emcc
export CXX_wasm32_unknown_emscripten=em++
export AR_wasm32_unknown_emscripten=emar

# naga-native's shared conversion module currently references types from every
# Naga front/back end even though exported functions are feature-gated. Build
# the pinned default feature set for correctness; a future narrow FFI wrapper
# can reduce size once this renderer path is proven.
cargo build \
  --manifest-path "$WORK_ROOT/naga-native/Cargo.toml" \
  --release \
  --locked \
  --target wasm32-unknown-emscripten \
  --target-dir "$TARGET_ROOT/naga-native"

cargo build \
  --manifest-path "$WORK_ROOT/spirv-webgpu-transform/ffi/Cargo.toml" \
  --release \
  --locked \
  --target wasm32-unknown-emscripten \
  --target-dir "$TARGET_ROOT/spirv-webgpu-transform"

NAGA_LIB="$TARGET_ROOT/naga-native/wasm32-unknown-emscripten/release/libnaga_native.a"
SPIRV_LIB="$TARGET_ROOT/spirv-webgpu-transform/wasm32-unknown-emscripten/release/libspirv_webgpu_transform_ffi.a"

test -s "$NAGA_LIB"
test -s "$SPIRV_LIB"

cp "$NAGA_LIB" "$GODOT_SOURCE/thirdparty/naga-native/libnaga_native.a"
cp "$SPIRV_LIB" "$GODOT_SOURCE/thirdparty/spirv-webgpu-transform/libspirv_webgpu_transform_ffi.a"

printf 'naga_native %s bytes\n' "$(stat -c %s "$NAGA_LIB")"
printf 'spirv_webgpu_transform_ffi %s bytes\n' "$(stat -c %s "$SPIRV_LIB")"
