#!/usr/bin/env bash
# models.txt の各モデルの digest を、source の tag が今指す manifest の sha256 に書き換える。
# digest の無い行には source の直後に足す (後ろの列はそのまま残す)。manifest を取得できなかった行は元のまま残して続け、最後に非 0 で終了する。
set -euo pipefail

models_file=${1:-"$(dirname "$0")/models.txt"}
# 権限を保ったまま置き換えるため、元のファイルを複製して書き込み先にする
tmp=$(mktemp "${models_file}.XXXXXX")
body=$(mktemp)
trap 'rm -f "$tmp" "$body"' EXIT
cp -p "$models_file" "$tmp"
failed=""

while IFS= read -r line || [[ -n $line ]]; do
  read -r alias source digest rest <<<"$line" || true
  if [[ -z ${alias:-} || $alias == '#'* ]]; then
    printf '%s\n' "$line"
    continue
  fi
  # digest の無い行では、3 列目は後ろの列 (要件) なので、digest として扱わない
  if [[ ${digest:-} != sha256:* ]]; then
    rest="${digest:-}${rest:+ $rest}"
    digest=""
  fi
  name=${source%:*}
  # pull-models.sh が受け付ける形と同じ
  if [[ ! ${source:-} =~ ^[A-Za-z0-9.-]+\.[A-Za-z]+(:[0-9]+)?/[^/:]+/[^/:]+:[^/:]+$ ]]; then
    echo "ERROR: source must be '<host>/<namespace>/<model>:<tag>': $line" >&2
    exit 1
  fi
  # Ollama 形式のレジストリは匿名の取得に、Ollama が pull で保存するのと同じ manifest を返す
  # (Ollama の User-Agent では署名付きの認証を求められる)。hf.co は huggingface.co へ redirect する
  url="https://${name%%/*}/v2/${name#*/}/manifests/${source##*:}"
  # 単体の manifest を返す tag だけを扱う (pull-models.sh の照合も、単体の manifest の digest を前提にしている)。
  # 改行も含めたバイト列をハッシュするため、本文はファイルで受ける
  if ! curl -fsSL --max-time 60 -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -o "$body" "$url" ||
    ! jq -e '.mediaType == "application/vnd.docker.distribution.manifest.v2+json" and (.layers | type == "array")' "$body" >/dev/null; then
    echo "WARNING: failed to fetch an Ollama manifest: $url" >&2
    failed="$failed $alias"
    printf '%s\n' "$line"
    continue
  fi
  new="sha256:$(shasum -a 256 "$body" | cut -d ' ' -f 1)"
  if [[ -z $digest ]]; then
    line="$alias $source $new${rest:+ $rest}"
  elif [[ $digest != "$new" ]]; then
    line=${line/"$digest"/"$new"}
  else
    printf '%s\n' "$line"
    continue
  fi
  echo "updated: $alias -> $new" >&2
  printf '%s\n' "$line"
done <"$models_file" >"$tmp"

mv "$tmp" "$models_file"
if [[ -n $failed ]]; then
  echo "ERROR: failed to resolve:$failed" >&2
  exit 1
fi
