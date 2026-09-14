#!/usr/bin/env bash
set -euo pipefail
profile=${1:?usage: verify-source.sh PROFILE [commit] [checkout]}
commit=${2:-"$(node scripts/profile.js "$profile" source.commit)"}
checkout=${3:-}
node scripts/profile.js "$profile" >/dev/null
[[ "$commit" =~ ^[a-f0-9]{40}$ ]] || { echo 'source commit must be a full 40-character lowercase SHA' >&2; exit 2; }
mirror=$(node scripts/profile.js "$profile" source.mirror_url)
upstream=$(node scripts/profile.js "$profile" source.upstream_url)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth=1 "$mirror" "$commit" || { echo 'commit is absent from XRIG mirror' >&2; exit 1; }
git -C "$tmp" cat-file -e "$commit^{commit}"
git -C "$tmp" fetch -q --depth=1 "$upstream" "$commit" || { echo 'commit is not reachable from upstream' >&2; exit 1; }
git -C "$tmp" cat-file -e "$commit^{commit}"
if [[ -n "$checkout" ]]; then
  [[ -d "$checkout/.git" ]] || { echo 'checkout is not a git repository' >&2; exit 1; }
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "$commit" ]] || { echo 'checkout commit differs from requested commit' >&2; exit 1; }
  [[ -z "$(git -C "$checkout" status --porcelain)" ]] || { echo 'source checkout must be clean' >&2; exit 1; }
fi
echo "Verified upstream-reachable XRIG mirror source $commit"
