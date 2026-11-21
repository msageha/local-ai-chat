#!/bin/sh
# models.txt の各モデルを Ollama に pull し、manifest の digest が一致したものだけをエイリアス名でコピーする。
# 一部のモデルが失敗しても残りを処理し、失敗があれば最後に非 0 で終了する。
set -u

models_file=${1:?usage: pull-models.sh <models.txt> <manifests-dir>}
# Ollama は <host>/<namespace>/<model>/<tag> に manifest を置く (ollama 0.34.4 で確認)
manifests_dir=${2:?usage: pull-models.sh <models.txt> <manifests-dir>}
if [ ! -r "$models_file" ]; then
  echo "ERROR: cannot read models file: $models_file" >&2
  exit 1
fi
failed=""

while read -r alias source digest _ || [ -n "$alias" ]; do
  case $alias in '' | '#'*) continue ;; esac
  if ! printf '%s\n' "$digest" | grep -qx 'sha256:[0-9a-f]\{64\}'; then
    echo "WARNING: skipping malformed line (expected '<alias> <source> sha256:<64 hex>'): $alias" >&2
    failed="$failed $alias"
    continue
  fi
  # alias は registry.ollama.ai/library/<alias>:latest として保存されるので、同じ形の source は
  # 照合の前の pull でいずれかの alias を上書きしうる。Ollama は名前の大文字小文字を区別しない
  case $(printf '%s' "$source" | tr '[:upper:]' '[:lower:]') in registry.ollama.ai/library/*:latest)
    echo "WARNING: source must not be registry.ollama.ai/library/<model>:latest: $alias ($source)" >&2
    failed="$failed $alias"
    continue
    ;;
  esac
  if ! ollama pull "$source"; then
    echo "WARNING: failed to pull $alias ($source)" >&2
    failed="$failed $alias"
    continue
  fi
  # 照合から alias への登録までの間に source の tag が別の pull で更新されても、照合した版だけを alias に載せるため、
  # この実行だけが使う名前に複製してから照合する。コンテナごとに PID は 1 になりうるので UUID で区別する
  staging="pull-models-$(cat /proc/sys/kernel/random/uuid)"
  if ! ollama cp "$source" "$staging"; then
    echo "WARNING: failed to copy $source to $staging" >&2
    failed="$failed $alias"
    continue
  fi
  actual="sha256:$(sha256sum "$manifests_dir/registry.ollama.ai/library/$staging/latest" | cut -d ' ' -f 1)"
  # tag が別の内容に更新されていたら、確かめていない版を alias に載せない (alias は前の版のまま残る)
  if [ "$actual" != "$digest" ]; then
    echo "WARNING: digest mismatch for $alias ($source): expected $digest, got $actual" >&2
    failed="$failed $alias"
  elif ollama cp "$staging" "$alias"; then
    echo "ready: $alias -> $source@$digest"
  else
    echo "WARNING: failed to copy $staging to $alias" >&2
    failed="$failed $alias"
  fi
  ollama rm "$staging" >/dev/null || echo "WARNING: failed to remove $staging" >&2
done < "$models_file"

if [ -n "$failed" ]; then
  echo "ERROR: failed to prepare:$failed" >&2
  exit 1
fi
