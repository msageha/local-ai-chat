#!/usr/bin/env bash
# compose.yaml の ollama/ollama イメージと mise.toml の ollama (Apple Silicon の構成でホストに入れる版) が
# 同じバージョンかを確かめる。Renovate は両者を別々に更新しうるので、食い違いを CI で止める。
set -euo pipefail

cd "$(dirname "$0")/.."
# ollama と ollama-init の両方の行から、digest 付きの版を読めたことを確かめる (読めない行があると比較から漏れるため)
image_lines=$(grep -c -E 'image: ollama/ollama([:@]|$)' compose.yaml || true)
pinned=$(sed -n -E 's#^[[:space:]]*image: ollama/ollama:([^@[:space:]]+)@sha256:[0-9a-f]{64}.*#\1#p' compose.yaml)
image_versions=$(sort -u <<<"$pinned")
mise_version=$(sed -n -E 's/^ollama = \{ version = "([^"]+)".*/\1/p' mise.toml)

if [[ -z $pinned || $(wc -l <<<"$pinned") -ne $image_lines || -z $mise_version ]]; then
  echo "ERROR: could not find the Ollama version in compose.yaml or mise.toml" >&2
  exit 1
fi
if [[ $image_versions != "$mise_version" ]]; then
  echo "ERROR: Ollama versions differ: compose.yaml=$(echo "$image_versions" | paste -sd, -) mise.toml=$mise_version" >&2
  exit 1
fi
