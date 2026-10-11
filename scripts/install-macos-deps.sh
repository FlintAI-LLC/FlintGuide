#!/usr/bin/env bash
set -euo pipefail

# Tauri 2.x macOS build dependencies for FlintGuide.
# Run once on a fresh dev or CI macOS machine: ./scripts/install-macos-deps.sh
#
# Xcode Command Line Tools provide clang, the SDKs, and the libclang that
# bindgen needs. cmake powers whisper-rs's whisper.cpp build.

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Xcode Command Line Tools (may prompt for interaction)..."
  xcode-select --install || true
fi

# Homebrew only publishes bottles for the newest few macOS releases. Once the
# runner image falls off that list `brew install llvm` compiles LLVM from
# source, which takes longer than the whole CI job budget. Resolve libclang
# from the Xcode toolchain first and only fall back to Homebrew when the
# toolchain genuinely lacks it.
find_libclang() {
  local dir
  for dir in \
    "$(xcode-select -p 2>/dev/null)/Toolchains/XcodeDefault.xctoolchain/usr/lib" \
    "$(xcode-select -p 2>/dev/null)/usr/lib" \
    "/Library/Developer/CommandLineTools/usr/lib"; do
    if [[ -e "${dir}/libclang.dylib" ]]; then
      echo "${dir}"
      return 0
    fi
  done
  return 1
}

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

missing=()
for tool in cmake pkg-config; do
  command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Missing ${missing[*]} and Homebrew is not installed (see https://brew.sh)." >&2
    exit 1
  fi
  brew install "${missing[@]}"
fi

if ! LIBCLANG_PATH="$(find_libclang)"; then
  echo "libclang not found in the Xcode toolchain — falling back to Homebrew llvm." >&2
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required for the llvm fallback (see https://brew.sh)." >&2
    exit 1
  fi
  brew install llvm
  LIBCLANG_PATH="$(brew --prefix llvm)/lib"
fi

if [[ ! -e "${LIBCLANG_PATH}/libclang.dylib" ]]; then
  echo "libclang.dylib not found at ${LIBCLANG_PATH}" >&2
  exit 1
fi

echo "LIBCLANG_PATH=${LIBCLANG_PATH}"

# Surface env to GitHub Actions when running under CI.
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "LIBCLANG_PATH=${LIBCLANG_PATH}" >> "${GITHUB_ENV}"
fi

echo "macOS dependencies installed. Verify with: cd src-tauri && cargo build"
