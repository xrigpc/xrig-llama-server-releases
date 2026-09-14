#!/usr/bin/env node
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const profilePath = process.argv[2];
if (!profilePath) throw new Error('usage: profile.js PROFILE [field]');
// JSON is valid YAML. Keeping the profile JSON-shaped makes the release
// contract dependency-free and unambiguous in GitHub Actions.
const p = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
const sha = v => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const commit = v => typeof v === 'string' && /^[a-f0-9]{40}$/.test(v);
for (const k of ['lane_id', 'stack_id', 'asset_prefix']) if (!/^[a-z0-9][a-z0-9.-]+$/.test(p[k] || '')) throw new Error(`invalid ${k}`);
if (p.label !== 'RX 7900 XTX (ROCm gfx1100)') throw new Error('invalid human-readable lane label');
if (p.lane_id !== 'rx7900xtx-rocm-gfx1100' || p.stack_id !== 'linux-amd-rx7900xtx-rocm-gfx1100') throw new Error('only the XTX v1 lane is permitted');
if (!commit(p.source?.commit) || !/^https:\/\/github\.com\/xrigpc\/llama\.cpp\.git$/.test(p.source?.mirror_url || '') || !/^https:\/\/github\.com\/ggml-org\/llama\.cpp\.git$/.test(p.source?.upstream_url || '')) throw new Error('invalid source contract');
if (!/^https:\/\/rocm\.nightlies\.amd\.com\//.test(p.therock?.url || '') || !sha(p.therock?.sha256) || !Number.isSafeInteger(p.therock?.size_bytes) || p.therock.size_bytes < 1) throw new Error('invalid AMD TheRock pin');
const c = p.cmake || {}; const expected = { GGML_HIP:'ON', AMDGPU_TARGETS:'gfx1100', GGML_HIP_GRAPHS:'ON', GGML_HIP_NO_VMM:'ON', GGML_HIP_MMQ_MFMA:'ON', GGML_HIP_ROCWMMA_FATTN:'ON', GGML_OPENMP:'ON', BUILD_SHARED_LIBS:'ON', CMAKE_BUILD_TYPE:'Release', GGML_NATIVE:'OFF', CMAKE_SKIP_RPATH:'ON' };
for (const [k,v] of Object.entries(expected)) if (c[k] !== v) throw new Error(`required CMake option ${k}=${v} missing`);
for (const forbidden of ['GGML_CUDA', 'GGML_VULKAN', 'CMAKE_INSTALL_RPATH', 'CMAKE_BUILD_RPATH']) if (c[forbidden] && c[forbidden] !== 'OFF') throw new Error(`forbidden CMake option ${forbidden}`);
if (process.argv[3]) {
  const value = process.argv[3].split('.').reduce((o, k) => o?.[k], p);
  if (value === undefined) process.exitCode = 2; else process.stdout.write(typeof value === 'object' ? JSON.stringify(value) : String(value));
}
