#!/bin/sh
# models.txt の各モデルを Ollama に pull し、manifest の digest が一致したものだけをエイリアス名でコピーする。
# 一部のモデルが失敗しても残りを処理し、失敗があれば最後に非 0 で終了する。
# 4 列目に mlx がある行は、環境変数 PULL_MLX_MODELS=1 のとき (Ollama が MLX を使える構成) だけ pull し、
# それ以外では失敗に数えずに飛ばす。
set -u

models_file=${1:?usage: pull-models.sh <models.txt> <models-dir>}
# Ollama は <models-dir>/manifests-v2/<host>/<namespace>/<model>/<tag> に、manifest を保存した blob への symlink を置く
# (ollama 0.40.17 で確認)。照合は symlink を辿って blob の中身をハッシュするので、blobs も読める必要がある
models_dir=${2:?usage: pull-models.sh <models.txt> <models-dir>}
if [ ! -r "$models_file" ]; then
  echo "ERROR: cannot read models file: $models_file" >&2
  exit 1
fi
failed=""

while read -r alias source digest requires _ || [ -n "$alias" ]; do
  case $alias in '' | '#'*) continue ;; esac
  if ! printf '%s\n' "$digest" | grep -qx 'sha256:[0-9a-f]\{64\}'; then
    echo "WARNING: skipping malformed line (expected '<alias> <source> sha256:<64 hex> [mlx]'): $alias" >&2
    failed="$failed $alias"
    continue
  fi
  # 短縮名や tag の省略は Ollama が既定の host・namespace と latest で補い、alias と同じ名前になりうるので、
  # source は <host>/<namespace>/<model>:<tag> の完全な名前に限る
  if ! printf '%s\n' "$source" | grep -qE '^[A-Za-z0-9.-]+\.[A-Za-z]+(:[0-9]+)?/[^/:]+/[^/:]+:[^/:]+$'; then
    echo "WARNING: source must be '<host>/<namespace>/<model>:<tag>': $alias ($source)" >&2
    failed="$failed $alias"
    continue
  fi
  # alias は ollama.com/library/<alias>:latest として保存され、registry.ollama.ai/library/ の名前も同じ場所に入るので、
  # この形の source は照合の前の pull でいずれかの alias を上書きしうる。Ollama は名前の大文字小文字を区別しない
  case $(printf '%s' "$source" | tr '[:upper:]' '[:lower:]') in registry.ollama.ai/library/*:latest | ollama.com/library/*:latest)
    echo "WARNING: source must not be <registry.ollama.ai|ollama.com>/library/<model>:latest: $alias ($source)" >&2
    failed="$failed $alias"
    continue
    ;;
  esac
  # 飛ばす行も上の形式の検査は通し、どの構成で起動しても models.txt の誤りを報告する
  case $requires in
  '') ;;
  mlx)
    if [ "${PULL_MLX_MODELS:-}" != 1 ]; then
      echo "skipped: $alias (requires Ollama with MLX on Apple Silicon)"
      continue
    fi
    ;;
  *)
    echo "WARNING: unknown requirement '$requires': $alias" >&2
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
  actual="sha256:$(sha256sum "$models_dir/manifests-v2/ollama.com/library/$staging/latest" | cut -d ' ' -f 1)"
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
