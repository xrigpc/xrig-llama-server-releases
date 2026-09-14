#!/usr/bin/env bash
set -euo pipefail
profile=${1:?usage: package-runtime.sh PROFILE BUILD_DIR RELEASE_VERSION OUT_DIR}
build=${2:?usage: package-runtime.sh PROFILE BUILD_DIR RELEASE_VERSION OUT_DIR}; version=${3:?usage: package-runtime.sh PROFILE BUILD_DIR RELEASE_VERSION OUT_DIR}; out=${4:?usage: package-runtime.sh PROFILE BUILD_DIR RELEASE_VERSION OUT_DIR}
[[ "$version" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}$ && ! -e "$out" ]] || { echo 'invalid version or existing output' >&2; exit 2; }
node scripts/profile.js "$profile" >/dev/null
runtime="$build/runtime"; [[ -x "$runtime/llama-server" ]] || { echo 'missing built runtime' >&2; exit 1; }
mkdir -p "$out/root/runtime/bin"
cp -a "$runtime/llama-server" "$out/root/runtime/bin/"
while IFS= read -r library; do [[ -e "$library" ]] && cp -aL "$library" "$out/root/runtime/bin/"; done < <(ldd "$runtime/llama-server" | awk '/=>/ {print $3}' | grep -E '/(lib(llama|ggml|mtmd)[^/]*\.so)' || true)
find "$runtime" -maxdepth 1 \( -type f -o -type l \) -name 'lib*.so*' -exec cp -a {} "$out/root/runtime/bin/" \;
[[ -f "$out/root/runtime/bin/libggml-hip.so.0" ]] || { echo 'HIP runtime closure is incomplete' >&2; exit 1; }
if find "$out/root" -type f -exec readelf -d {} \; 2>/dev/null | grep -E '(RPATH|RUNPATH)'; then echo 'RPATH is forbidden' >&2; exit 1; fi
prefix=$(node scripts/profile.js "$profile" asset_prefix); archive="$out/${prefix}-${version}.tar.gz"
tar -C "$out/root" -czf "$archive" runtime
sha256sum "$archive" > "$archive.sha256"; stat -c '%s' "$archive" > "$archive.size"
find "$out/root/runtime/bin" -maxdepth 1 -printf '%P\n' | sort > "$out/runtime-closure.txt"
