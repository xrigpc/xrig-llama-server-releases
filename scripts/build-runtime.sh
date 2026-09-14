#!/usr/bin/env bash
set -euo pipefail
profile=${1:?usage: build-runtime.sh PROFILE SOURCE_DIR OUT_DIR}
source_dir=${2:?usage: build-runtime.sh PROFILE SOURCE_DIR OUT_DIR}
out=${3:?usage: build-runtime.sh PROFILE SOURCE_DIR OUT_DIR}
[[ ! -e "$out" ]] || { echo 'output already exists' >&2; exit 2; }
node scripts/profile.js "$profile" >/dev/null
scripts/verify-source.sh "$profile" "$(node scripts/profile.js "$profile" source.commit)" "$source_dir"
mkdir -p "$out"; archive="$out/therock.tar.gz"; rocm="$out/rocm"; build="$out/build"
url=$(node scripts/profile.js "$profile" therock.url); expected_sha=$(node scripts/profile.js "$profile" therock.sha256); expected_size=$(node scripts/profile.js "$profile" therock.size_bytes)
curl --fail --location --retry 3 --output "$archive" "$url"
[[ "$(stat -c %s "$archive")" == "$expected_size" ]] && [[ "$(sha256sum "$archive" | awk '{print $1}')" == "$expected_sha" ]] || { echo 'TheRock size or SHA-256 mismatch' >&2; exit 1; }
mkdir "$rocm"; tar -xzf "$archive" -C "$rocm" --strip-components=1
clang="$rocm/lib/llvm/bin/clang++"; [[ -x "$clang" ]] || { echo 'TheRock HIP compiler missing' >&2; exit 1; }
ROCM_PATH="$rocm" HIPCXX="$clang" cmake -S "$source_dir" -B "$build" -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 -DGGML_HIP_GRAPHS=ON -DGGML_HIP_NO_VMM=ON -DGGML_HIP_MMQ_MFMA=ON -DGGML_HIP_ROCWMMA_FATTN=ON -DGGML_OPENMP=ON -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF -DCMAKE_SKIP_RPATH=ON -DGGML_CUDA=OFF -DGGML_VULKAN=OFF -DCMAKE_HIP_COMPILER="$clang" -DCMAKE_PREFIX_PATH="$rocm"
cmake --build "$build" --target llama-server --parallel "$(nproc)"
mkdir "$out/runtime"; cp -a "$build/bin/." "$out/runtime/"
[[ -x "$out/runtime/llama-server" ]] || { echo 'llama-server was not built' >&2; exit 1; }
if readelf -d "$out/runtime/llama-server" | grep -E '(RPATH|RUNPATH)' >/dev/null; then echo 'host RPATH is forbidden' >&2; exit 1; fi
