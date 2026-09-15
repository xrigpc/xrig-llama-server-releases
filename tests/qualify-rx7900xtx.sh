#!/usr/bin/env bash
# Runs on the protected RX 7900 XTX self-hosted runner after archive extraction.
set -euo pipefail
archive=${1:?usage: qualify-rx7900xtx.sh RUNTIME_ARCHIVE PROFILE2_ARGUMENTS_FILE}
args=${2:?usage: qualify-rx7900xtx.sh RUNTIME_ARCHIVE PROFILE2_ARGUMENTS_FILE}
[[ -n ${XRIG_QUALIFY_MODEL:-} && -n ${XRIG_QUALIFY_MMPROJ:-} && -n ${XRIG_QUALIFY_IMAGE:-} ]] || { echo 'qualification model, projector, and image paths are required' >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; tar -xzf "$archive" -C "$tmp"
bin="$tmp/runtime/bin/llama-server"; [[ -x "$bin" ]]; readelf -d "$bin" | grep -E '(RPATH|RUNPATH)' && exit 1 || true
[[ -s "$args" ]] || exit 1; grep -q -- '--ctx-size 124416\|--ctx-size=124416' "$args"
rocm_info=${XRIG_QUALIFY_ROCMINFO:-rocminfo}
grep -q 'gfx1100' <(ROCR_VISIBLE_DEVICES=0 "$rocm_info" 2>/dev/null)
mapfile -t argv < "$args"
ROCR_VISIBLE_DEVICES=0 LD_LIBRARY_PATH="$tmp/runtime/bin:${XRIG_QUALIFY_ROCM_LIB:-}" "$bin" --model "$XRIG_QUALIFY_MODEL" --mmproj "$XRIG_QUALIFY_MMPROJ" "${argv[@]}" >"$tmp/server.log" 2>&1 & pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 1 60); do curl -fsS http://127.0.0.1:8088/health >"$tmp/health.json" && break; sleep 1; done
grep -q . "$tmp/health.json"
curl -fsS http://127.0.0.1:8088/v1/chat/completions -H 'content-type: application/json' --data '{"model":"qwen3.8-27b-profile2-xhigh","messages":[{"role":"user","content":"Reply with OK."}],"max_tokens":8}' >"$tmp/text.json"
grep -q 'choices' "$tmp/text.json"
image_b64=$(base64 -w0 "$XRIG_QUALIFY_IMAGE")
curl -fsS http://127.0.0.1:8088/v1/chat/completions -H 'content-type: application/json' --data "{\"model\":\"qwen3.8-27b-profile2-xhigh\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"What is visible?\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$image_b64\"}}]}],\"max_tokens\":8}" >"$tmp/vision.json"
grep -q 'choices' "$tmp/vision.json"
printf '%s\n' '{"health":true,"text_inference":true,"vision_projector":true,"rocr_visible_devices":"0","gpu_arch":"gfx1100","profile2_arguments_match":true}'
