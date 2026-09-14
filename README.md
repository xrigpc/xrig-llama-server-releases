# XRIG llama-server releases

This repository is the release-control plane for XRIG's portable
`llama-server` runtime. `xrigpc/llama.cpp` remains a clean mirror of
`ggml-org/llama.cpp`; it receives no XRIG source patches.

Only the RX 7900 XTX ROCm `gfx1100` lane is enabled in v1. GitHub Releases
contain only XRIG-built runtime archives and their signed evidence. AMD's
TheRock archive is downloaded directly from the pinned official AMD URL in the
signed Supabase stack descriptor.

The lane profile is a build candidate, not production authority. A candidate
becomes selectable only after `Publish Profile` publishes its immutable signed
descriptor, stack index, config revision, and finally the catalogue row to
Supabase.

Never replace a release asset, stack version, descriptor, or config revision.
The local backend's historic ROCm candidates are not inputs to this repository.
