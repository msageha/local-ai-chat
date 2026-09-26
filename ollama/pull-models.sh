#!/bin/sh
# models.txt の各モデルを Ollama に pull し、エイリアス名でコピーする。
# 一部のモデルが失敗しても残りを処理し、失敗があれば最後に非 0 で終了する。
set -u

models_file=${1:?usage: pull-models.sh <models.txt>}
if [ ! -r "$models_file" ]; then
  echo "ERROR: cannot read models file: $models_file" >&2
  exit 1
fi
failed=""

while read -r alias source _ || [ -n "$alias" ]; do
  case $alias in '' | '#'*) continue ;; esac
  if [ -z "$source" ]; then
    echo "WARNING: skipping malformed line (expected '<alias> <source>'): $alias" >&2
    failed="$failed $alias"
    continue
  fi
  if ollama pull "$source" && ollama cp "$source" "$alias"; then
    echo "ready: $alias -> $source"
  else
    echo "WARNING: failed to prepare $alias ($source)" >&2
    failed="$failed $alias"
  fi
done < "$models_file"

if [ -n "$failed" ]; then
  echo "ERROR: failed to prepare:$failed" >&2
  exit 1
fi
