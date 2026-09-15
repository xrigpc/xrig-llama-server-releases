#!/usr/bin/env bash
# Publishes only signed metadata. Runtime bytes stay on GitHub; TheRock stays
# on AMD. Catalogue is intentionally the final mutable write.
set -euo pipefail
profile=${1:?usage: publish-supabase.sh PROFILE RELEASE_TAG PROFILE_REVISION RECEIPT_DIR CONFIG_JSON}
tag=${2:?usage: publish-supabase.sh PROFILE RELEASE_TAG PROFILE_REVISION RECEIPT_DIR CONFIG_JSON}
revision=${3:?usage: publish-supabase.sh PROFILE RELEASE_TAG PROFILE_REVISION RECEIPT_DIR CONFIG_JSON}
receipt_dir=${4:?usage: publish-supabase.sh PROFILE RELEASE_TAG PROFILE_REVISION RECEIPT_DIR CONFIG_JSON}
config=${5:?usage: publish-supabase.sh PROFILE RELEASE_TAG PROFILE_REVISION RECEIPT_DIR CONFIG_JSON}
[[ "$revision" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}$ ]] || { echo 'profile revision must be readable and immutable' >&2; exit 2; }
node scripts/profile.js "$profile" >/dev/null
[[ -n ${SUPABASE_URL:-} && -n ${SUPABASE_SERVICE_ROLE_KEY:-} && -n ${GITHUB_REPOSITORY:-} ]] || { echo 'SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and GITHUB_REPOSITORY are required' >&2; exit 2; }
receipt="$receipt_dir/receipt.json"; qualification="$receipt_dir/qualification.json"; [[ -f "$receipt" && -f "$receipt.sig" && -f "$qualification" && -f "$config" ]] || { echo 'receipt, signature, qualification, and config are required' >&2; exit 1; }
scripts/verify-artifact.sh "$receipt" "$receipt.sig"
commit=$(node -e 'const x=require(require("path").resolve(process.argv[1])); if(!/^[a-f0-9]{40}$/.test(x.llama_commit))throw Error("bad receipt source"); console.log(x.llama_commit)' "$receipt")
scripts/verify-source.sh "$profile" "$commit"
node - "$profile" "$receipt" "$qualification" "$config" "$revision" <<'NODE'
const fs=require('fs'); const p=JSON.parse(fs.readFileSync(process.argv[2])); const r=JSON.parse(fs.readFileSync(process.argv[3])); const q=JSON.parse(fs.readFileSync(process.argv[4])); const c=JSON.parse(fs.readFileSync(process.argv[5])); const rev=process.argv[6];
const die=x=>{throw Error(x)}; if(r.therock.url!==p.therock.url||r.therock.sha256!==p.therock.sha256||r.therock.size_bytes!==p.therock.size_bytes)die('TheRock receipt differs from reviewed pin');
if(!q.health||!q.text_inference||!q.vision_projector||q.rocr_visible_devices!=='0'||q.gpu_arch!=='gfx1100'||!q.profile2_arguments_match)die('qualification receipt is incomplete');
if(c.id!=='qwen3.8-27b-rx7900xtx-rocm-profile2'||c.version!==rev||c.runtime?.ref?.stack_id!==p.stack_id||c.runtime.ref.version!==r.release_version)die('config runtime reference or revision mismatch');
NODE
asset=$(node -e 'console.log(require(require("path").resolve(process.argv[1])).runtime.asset_name)' "$receipt")
github_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/${asset}"
github_sig="${github_url}.sig"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# The workflow's authenticated release download is the asset-inventory check.
# Verify its exact runtime bytes and detached signature locally before any
# Supabase write; do not depend on redirect/CDN behavior in this environment.
[[ -f "$receipt_dir/$asset" && -f "$receipt_dir/$asset.sig" ]] || { echo 'release evidence lacks the required runtime asset or signature' >&2; exit 1; }
runtime_sha=$(sha256sum "$receipt_dir/$asset" | awk '{print $1}')
receipt_sha=$(node -e 'console.log(require(require("path").resolve(process.argv[1])).runtime.sha256)' "$receipt")
[[ "$runtime_sha" == "$receipt_sha" ]] || { echo 'downloaded runtime hash differs from signed receipt' >&2; exit 1; }
scripts/verify-artifact.sh "$receipt_dir/$asset" "$receipt_dir/$asset.sig"
stack=$(node scripts/profile.js "$profile" stack_id); version=$(node -e 'console.log(require(require("path").resolve(process.argv[1])).release_version)' "$receipt")
node - "$profile" "$receipt" "$github_url" "$github_sig" "$work/descriptor.json" <<'NODE'
const fs=require('fs'); const p=JSON.parse(fs.readFileSync(process.argv[2])); const r=JSON.parse(fs.readFileSync(process.argv[3])); const [url,sig,out]=process.argv.slice(4);
const closure=fs.readFileSync(require('path').join(require('path').dirname(process.argv[3]),'runtime-closure.txt'),'utf8').trim().split('\n').filter(Boolean).map(x=>({path:'runtime/bin/'+x,sha256:'closure-hash-recorded-in-build-receipt'}));
// Closure hashes are required in a production receipt. Do not allow a hand-written descriptor.
if(!r.runtime_closure || !Array.isArray(r.runtime_closure) || !r.runtime_closure.length) throw Error('receipt lacks runtime closure hashes');
const d={schema_version:1,stack_id:p.stack_id,version:r.release_version,os:'linux',arch:'amd64',vendor:'amd',backend:'rocm',label:p.label,executable:'runtime/bin/llama-server',backend_file:'runtime/bin/libggml-hip.so.0',library_dirs:['runtime/bin','rocm/lib'],environment:{ROCM_PATH:'${STACK_ROOT}/rocm',HIP_PATH:'${STACK_ROOT}/rocm',HIP_DEVICE_LIB_PATH:'${STACK_ROOT}/rocm/amdgcn/bitcode'},gpu_arch:'gfx1100',llama_commit:r.llama_commit,prerequisites:{distro:'ubuntu',distro_versions:['24.04']},artifacts:[{id:'xrig-llama-server',url,signature_url:sig,sha256:r.runtime.sha256,size_bytes:r.runtime.size_bytes,format:'tar.gz',destination:'.'},{id:'amd-therock',url:r.therock.url,sha256:r.therock.sha256,size_bytes:r.therock.size_bytes,format:'tar.gz',destination:'rocm'}],files:r.runtime_closure}; fs.writeFileSync(out,JSON.stringify(d,null,2)+'\n');
NODE
scripts/sign-artifact.sh "$work/descriptor.json"
base="${SUPABASE_URL%/}/storage/v1/object/xrig-configs"
put_immutable() {
  local object=$1 input=$2 status existing
  status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H 'x-upsert: false' --data-binary @"$input" "$base/$object")
  [[ "$status" =~ ^2 ]] && return 0
  # A prior interrupted run may already have created this immutable object.
  # Resume only if its public bytes are exactly the bytes this run generated.
  existing="$work/existing-$(basename "$object")"
  status=$(curl -sS -o "$existing" -w '%{http_code}' "${SUPABASE_URL%/}/storage/v1/object/public/xrig-configs/$object")
  [[ "$status" == 200 ]] && cmp -s "$input" "$existing" && return 0
  echo "immutable Supabase object write failed or conflicts: $object" >&2
  return 1
}
# Immutable objects first. A failed write ends before any active catalogue change.
put_immutable "stacks/v1/${stack}-${version}.json" "$work/descriptor.json"; put_immutable "stacks/v1/${stack}-${version}.json.sig" "$work/descriptor.json.sig"
public="${SUPABASE_URL%/}/storage/v1/object/public/xrig-configs"
get_public_or_initial() {
  local object=$1 output=$2 initial=$3 status
  status=$(curl -sS -o "$output" -w '%{http_code}' "$public/$object")
  if [[ "$status" == 200 ]]; then return 0; fi
  [[ "$status" == 400 || "$status" == 404 ]] && node - "$output" <<'NODE'
const fs=require('fs'); const x=JSON.parse(fs.readFileSync(process.argv[2]));
if(!/not.?found|object/i.test(JSON.stringify(x))) process.exit(1);
NODE
  printf '%s\n' "$initial" > "$output"
}
index_status=$(curl -sS -o "$work/index.json" -w '%{http_code}' "$public/stacks/v1/index.json")
if [[ "$index_status" == 200 ]]; then
  curl -fsS "$public/stacks/v1/index.json.sig" -o "$work/index.json.sig"
  scripts/verify-artifact.sh "$work/index.json" "$work/index.json.sig"
else
  [[ "$index_status" == 400 || "$index_status" == 404 ]] && node - "$work/index.json" <<'NODE'
const fs=require('fs'); const x=JSON.parse(fs.readFileSync(process.argv[2]));
if(!/not.?found|object/i.test(JSON.stringify(x))) process.exit(1);
NODE
  printf '%s\n' '{"schema_version":1,"stacks":[]}' > "$work/index.json"
fi
descriptor_url="$public/stacks/v1/${stack}-${version}.json"; descriptor_sha=$(sha256sum "$work/descriptor.json" | awk '{print $1}'); descriptor_size=$(stat -c %s "$work/descriptor.json")
node - "$work/index.json" "$stack" "$version" "$descriptor_url" "$descriptor_sha" "$descriptor_size" <<'NODE'
const fs=require('fs');const [f,stack,version,url,sha,size]=process.argv.slice(2);const x=JSON.parse(fs.readFileSync(f));if(!Array.isArray(x.stacks))throw Error('invalid stack index');if(x.stacks.some(e=>e.stack_id===stack&&e.version===version))throw Error('stack version already exists');x.stacks.push({stack_id:stack,version,descriptor_url:url,signature_url:url+'.sig',sha256:sha,size_bytes:Number(size)});fs.writeFileSync(f,JSON.stringify(x,null,2)+'\n');
NODE
scripts/sign-artifact.sh "$work/index.json"; curl -fsS -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H 'x-upsert: true' --data-binary @"$work/index.json" "$base/stacks/v1/index.json" >/dev/null; curl -fsS -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H 'x-upsert: true' --data-binary @"$work/index.json.sig" "$base/stacks/v1/index.json.sig" >/dev/null
scripts/sign-artifact.sh "$config" "$work/config.sig"; put_immutable "configs/qwen3.8-27b-rx7900xtx-rocm-profile2/${revision}.json" "$config"; put_immutable "configs/qwen3.8-27b-rx7900xtx-rocm-profile2/${revision}.json.sig" "$work/config.sig"
# The catalogue is the only active mutable selection, so it is always last.
get_public_or_initial "catalogues/v2/index.json" "$work/catalogue.json" '[]'
config_sha=$(sha256sum "$config" | awk '{print $1}'); config_url="$public/configs/qwen3.8-27b-rx7900xtx-rocm-profile2/${revision}.json"
node - "$work/catalogue.json" "$revision" "$config_url" "$config_sha" <<'NODE'
const fs=require('fs');const [f,v,url,sha]=process.argv.slice(2);let x=JSON.parse(fs.readFileSync(f));if(!Array.isArray(x))throw Error('invalid catalogue');x=x.filter(e=>e.id!=='qwen3.8-27b-rx7900xtx-rocm-profile2');x.push({id:'qwen3.8-27b-rx7900xtx-rocm-profile2',config_version:v,schema_version:2,status:'stable',vendor:'amd',gpu_tags:['RX 7900 XTX'],os:['linux'],backend:'rocm',min_vram_gb:24,min_ram_gb:30,config_url:url,config_sha256:sha,updated_at:new Date().toISOString(),is_active:true,gpu_profile:'linux-amd-rx7900xtx-rocm-gfx1100',is_factory_default:true});fs.writeFileSync(f,JSON.stringify(x,null,2)+'\n');
NODE
curl -fsS -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H 'x-upsert: true' --data-binary @"$work/catalogue.json" "$base/catalogues/v2/index.json" >/dev/null
echo "Published descriptor, index, config revision, and catalogue (last)."
