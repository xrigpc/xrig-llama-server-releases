const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const {MAX_SIGNED_ARTIFACT_BYTES, assertSignedArtifactSizes} = require(path.join(root, 'scripts/stack-limits.js'));
assert.strictEqual(MAX_SIGNED_ARTIFACT_BYTES, 256 * 1024 * 1024);
const art = (id, size, signed) => ({id, size_bytes: size, ...(signed ? {signature_url: 'https://x/a.sig'} : {})});
// a self-signed artifact above the cap is refused, at the cap accepted
assert.throws(() => assertSignedArtifactSizes({artifacts: [art('xrig-llama-runtime', 1105574203, true)]}), /carries its own signature/);
assertSignedArtifactSizes({artifacts: [art('xrig-llama-server', MAX_SIGNED_ARTIFACT_BYTES, true)]});
// a large artifact with no signature of its own (pinned by the signed descriptor) is fine
assertSignedArtifactSizes({artifacts: [art('amd-therock', 3788461914, false), art('xrig-llama-runtime', 1105574203, false)]});
// the publisher runs the check on every descriptor it writes, before writing it
const publisher = fs.readFileSync(path.join(root, 'scripts/publish-supabase.sh'), 'utf8');
assert.ok(/assertSignedArtifactSizes\(d\);fs\.writeFileSync\(out,/.test(publisher), 'publish-supabase.sh writes a descriptor without the size check');
console.log('stack limits passed');
