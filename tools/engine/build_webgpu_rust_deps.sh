#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/engine/source-lock.json"
GODOT_SOURCE="${1:-$ROOT/build/webgpu-port-candidate/godot}"
WORK_ROOT="${2:-$ROOT/build/webgpu-rust-deps}"

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
PY
)

NAGA_REPO="${VALUES[0]}"
NAGA_SHA="${VALUES[1]}"
SPIRV_REPO="${VALUES[2]}"
SPIRV_SHA="${VALUES[3]}"

# The Godot bridge deliberately carries TAG files instead of the archives.
# Refuse to build if its declared dependency identity differs from our lock.
test "$(tr -d '\r\n' < "$GODOT_SOURCE/thirdparty/naga-native/TAG")" = "$NAGA_SHA"
test "$(tr -d '\r\n' < "$GODOT_SOURCE/thirdparty/spirv-webgpu-transform/TAG")" = "$SPIRV_SHA"

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"

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

rustup target add wasm32-unknown-emscripten

# naga-native generates Rust FFI bindings from its C header during the build.
# Bindgen otherwise discovers the host's /usr/include even though rustc targets
# Emscripten. Force Clang to use the same target/sysroot as emcc.
EMSCRIPTEN_SYSROOT="${EMSDK:?EMSDK must be set by the Emscripten environment}/upstream/emscripten/cache/sysroot"
test -d "$EMSCRIPTEN_SYSROOT"
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="--target=wasm32-unknown-emscripten --sysroot=$EMSCRIPTEN_SYSROOT"
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten_unknown="${BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten}"
export CC_wasm32_unknown_emscripten=emcc
export CXX_wasm32_unknown_emscripten=em++
export AR_wasm32_unknown_emscripten=emar

# Keep the translator minimal: Godot only needs SPIR-V input, validation and
# WGSL output from this C FFI library.
cargo build   --manifest-path "$WORK_ROOT/naga-native/Cargo.toml"   --release   --locked   --target wasm32-unknown-emscripten   --no-default-features   --features spv-in,wgsl-out

cargo build   --manifest-path "$WORK_ROOT/spirv-webgpu-transform/ffi/Cargo.toml"   --release   --locked   --target wasm32-unknown-emscripten

NAGA_LIB="$WORK_ROOT/naga-native/target/wasm32-unknown-emscripten/release/libnaga_native.a"
SPIRV_LIB="$WORK_ROOT/spirv-webgpu-transform/target/wasm32-unknown-emscripten/release/libspirv_webgpu_transform_ffi.a"

test -s "$NAGA_LIB"
test -s "$SPIRV_LIB"

cp "$NAGA_LIB" "$GODOT_SOURCE/thirdparty/naga-native/libnaga_native.a"
cp "$SPIRV_LIB" "$GODOT_SOURCE/thirdparty/spirv-webgpu-transform/libspirv_webgpu_transform_ffi.a"

printf 'naga_native %s bytes\n' "$(stat -c %s "$NAGA_LIB")"
printf 'spirv_webgpu_transform_ffi %s bytes\n' "$(stat -c %s "$SPIRV_LIB")"
