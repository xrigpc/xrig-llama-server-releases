'use strict';
// Vertex refuses an artifact that carries its own detached signature above this size
// (xrig-llama-backend internal/stacksetup maxSignedArtifactBytes): verifying an Ed25519
// signature means holding the whole artifact in memory. A larger artifact (the runtime
// closure, TheRock) is published pinned by size and SHA-256 in the signed descriptor alone,
// with no signature_url, and Vertex hashes it as it streams. Keep this equal to Vertex's
// constant: Vertex's TestSignedArtifactCapMatchesPublisher reads this file.
const MAX_SIGNED_ARTIFACT_BYTES = 268435456;

function assertSignedArtifactSizes(descriptor) {
  for (const a of (descriptor && descriptor.artifacts) || []) {
    if (a.signature_url && Number(a.size_bytes) > MAX_SIGNED_ARTIFACT_BYTES) {
      throw new Error(`artifact ${a.id} is ${a.size_bytes} bytes and carries its own signature; Vertex verifies such artifacts only up to ${MAX_SIGNED_ARTIFACT_BYTES} bytes. Publish it pinned by size and SHA-256 in the signed descriptor alone (no signature_url).`);
    }
  }
}

module.exports = {MAX_SIGNED_ARTIFACT_BYTES, assertSignedArtifactSizes};
