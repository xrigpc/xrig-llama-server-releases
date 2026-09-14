#!/usr/bin/env bash
set -euo pipefail
profile=${1:?usage: generate-stack-metadata.sh PROFILE RELEASE_VERSION PACKAGE_DIR OUT_DIR}
version=${2:?usage: generate-stack-metadata.sh PROFILE RELEASE_VERSION PACKAGE_DIR OUT_DIR}; package=${3:?usage: generate-stack-metadata.sh PROFILE RELEASE_VERSION PACKAGE_DIR OUT_DIR}; out=${4:?usage: generate-stack-metadata.sh PROFILE RELEASE_VERSION PACKAGE_DIR OUT_DIR}
node scripts/profile.js "$profile" >/dev/null; [[ ! -e "$out" ]] || { echo 'output exists' >&2; exit 2; }; mkdir -p "$out"
prefix=$(node scripts/profile.js "$profile" asset_prefix); archive="$package/${prefix}-${version}.tar.gz"; [[ -f "$archive" ]] || { echo 'archive missing' >&2; exit 1; }
sha=$(sha256sum "$archive" | awk '{print $1}'); size=$(stat -c %s "$archive"); commit=$(node scripts/profile.js "$profile" source.commit); stack=$(node scripts/profile.js "$profile" stack_id); amd_url=$(node scripts/profile.js "$profile" therock.url); amd_sha=$(node scripts/profile.js "$profile" therock.sha256); amd_size=$(node scripts/profile.js "$profile" therock.size_bytes)
node - "$out/receipt.json" "$version" "$commit" "$archive" "$sha" "$size" "$amd_url" "$amd_sha" "$amd_size" "$package/root/runtime/bin" <<'NODE'
const fs=require('fs'), crypto=require('crypto'), path=require('path'); const [f,version,commit,archive,sha,size,amdURL,amdSHA,amdSize,bin]=process.argv.slice(2);
const digest=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const runtime_closure=fs.readdirSync(bin,{withFileTypes:true}).filter(e=>e.isFile()||e.isSymbolicLink()).map(e=>({path:'runtime/bin/'+e.name,sha256:digest(path.join(bin,e.name))})).sort((a,b)=>a.path.localeCompare(b.path));
if(!runtime_closure.some(x=>x.path==='runtime/bin/llama-server')||!runtime_closure.some(x=>x.path==='runtime/bin/libggml-hip.so.0'))throw Error('runtime closure missing required files');
fs.writeFileSync(f, JSON.stringify({schema_version:1,release_version:version,llama_commit:commit,runtime:{asset_name:path.basename(archive),sha256:sha,size_bytes:Number(size)},runtime_closure,therock:{url:amdURL,sha256:amdSHA,size_bytes:Number(amdSize)},build:{gpu_arch:'gfx1100',cmake:{GGML_HIP:'ON',AMDGPU_TARGETS:'gfx1100',GGML_HIP_GRAPHS:'ON',GGML_HIP_NO_VMM:'ON',GGML_HIP_MMQ_MFMA:'ON',GGML_HIP_ROCWMMA_FATTN:'ON',GGML_NATIVE:'OFF',CMAKE_SKIP_RPATH:'ON'}}},null,2)+'\n');
NODE
cp "$package/runtime-closure.txt" "$out/runtime-closure.txt"
echo "${stack}-${version}" > "$out/stack-version.txt"
