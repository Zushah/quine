#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT_DIR/out"

mkdir -p "$OUT_DIR"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
}

need_cmd nasm
need_cmd gcc
need_cmd g++
need_cmd rustc
need_cmd javac
need_cmd java
need_cmd node
need_cmd cmp
need_cmd head

PY_CMD=()
if command -v python3 >/dev/null 2>&1; then
  PY_CMD=(python3)
elif command -v python >/dev/null 2>&1; then
  PY_CMD=(python)
elif command -v py >/dev/null 2>&1; then
  PY_CMD=(py -3)
else
  echo "error: python runner not found (tried: python3, python, py -3)" >&2
  exit 1
fi

run_and_verify() {
  local step="$1"
  local output_file="$2"
  local expected_file="$3"
  shift 3

  echo "[$step] writing $(basename "$output_file")"
  "$@" >"$output_file"

  if cmp -s "$output_file" "$expected_file"; then
    echo "  ok: matches $(basename "$expected_file")"
    return
  fi

  echo "  FAIL: differs from $(basename "$expected_file")" >&2
  echo "  First byte differences (byte-pos expected->actual):" >&2
  cmp -l "$expected_file" "$output_file" | head -n 10 >&2 || true
  exit 1
}

compile_rust() {
  local src="$1"
  local out="$2"
  local rust_sysroot rust_sysroot_unix gnu_lib_dir
  rust_sysroot="$(rustc --print sysroot | tr -d '\r')"
  if command -v cygpath >/dev/null 2>&1; then
    rust_sysroot_unix="$(cygpath -u "$rust_sysroot")"
  else
    rust_sysroot_unix="$rust_sysroot"
  fi

  gnu_lib_dir="$rust_sysroot_unix/lib/rustlib/x86_64-pc-windows-gnu/lib"
  if [[ ! -d "$gnu_lib_dir" ]]; then
    if command -v rustup >/dev/null 2>&1; then
      echo "Rust GNU target not found; installing x86_64-pc-windows-gnu via rustup..."
      rustup target add x86_64-pc-windows-gnu
    fi
  fi

  if [[ -d "$gnu_lib_dir" ]]; then
    rustc "$src" -O --target x86_64-pc-windows-gnu -C linker=gcc -o "$out"
    return
  fi

  echo "error: Rust target x86_64-pc-windows-gnu is not installed and MSVC linking is unavailable in this shell." >&2
  echo "       Run: rustup target add x86_64-pc-windows-gnu" >&2
  exit 1
}

echo "Building relay into: $OUT_DIR"

rm -f "$OUT_DIR"/relay.obj \
      "$OUT_DIR"/relay_asm.exe \
      "$OUT_DIR"/relay_c.exe \
      "$OUT_DIR"/relay_rust.exe \
      "$OUT_DIR"/relay_cpp.exe \
      "$OUT_DIR"/Relay.class \
      "$OUT_DIR"/from_asm.c \
      "$OUT_DIR"/from_c.rs \
      "$OUT_DIR"/from_rust.cpp \
      "$OUT_DIR"/from_cpp.java \
      "$OUT_DIR"/from_java.js \
      "$OUT_DIR"/from_js.py \
      "$OUT_DIR"/from_py.asm || true

nasm -f win64 "$ROOT_DIR/relay.asm" -o "$OUT_DIR/relay.obj"
gcc "$OUT_DIR/relay.obj" -o "$OUT_DIR/relay_asm.exe"
gcc "$ROOT_DIR/relay.c" -o "$OUT_DIR/relay_c.exe"
compile_rust "$ROOT_DIR/relay.rs" "$OUT_DIR/relay_rust.exe"
g++ "$ROOT_DIR/relay.cpp" -O2 -o "$OUT_DIR/relay_cpp.exe"
javac -d "$OUT_DIR" "$ROOT_DIR/Relay.java"

echo "Running relay and verifying each hop"
run_and_verify "asm -> c" "$OUT_DIR/from_asm.c" "$ROOT_DIR/relay.c" "$OUT_DIR/relay_asm.exe"
run_and_verify "c -> rust" "$OUT_DIR/from_c.rs" "$ROOT_DIR/relay.rs" "$OUT_DIR/relay_c.exe"
run_and_verify "rust -> cpp" "$OUT_DIR/from_rust.cpp" "$ROOT_DIR/relay.cpp" "$OUT_DIR/relay_rust.exe"
run_and_verify "cpp -> java" "$OUT_DIR/from_cpp.java" "$ROOT_DIR/Relay.java" "$OUT_DIR/relay_cpp.exe"
run_and_verify "java -> js" "$OUT_DIR/from_java.js" "$ROOT_DIR/relay.js" java -cp "$OUT_DIR" Relay
run_and_verify "js -> python" "$OUT_DIR/from_js.py" "$ROOT_DIR/relay.py" node "$ROOT_DIR/relay.js"
run_and_verify "python -> asm" "$OUT_DIR/from_py.asm" "$ROOT_DIR/relay.asm" "${PY_CMD[@]}" "$ROOT_DIR/relay.py"

echo "Success: full 7-language relay verified."
