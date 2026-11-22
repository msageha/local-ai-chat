#!/usr/bin/env bash
# Apple Silicon の構成で、text アプリの Ollama をホストで起動する (コンテナからは Metal と MLX を使えないため)。Ctrl-C で止める
set -euo pipefail

CDPATH='' cd -- "$(dirname "$0")/../.."
if [[ $(uname -sm) != "Darwin arm64" ]]; then
  echo "serve runs Ollama on the host and needs macOS on Apple Silicon" >&2
  exit 1
fi
# [env] に書いた secret を、長く動き続けるホストの Ollama に引き継がせない
unset WEBUI_SECRET_KEY
# bind 先・ポート・Ollama の設定は compose が決めた値を使い、コンテナで動かすときと揃える
config=$(docker compose -f apps/text/compose.yaml -f apps/text/compose.apple.yaml config --format json)
# compose.apple.yaml の ollama サービスは --to host.docker.internal:<port> へ転送するので、そのポートで待ち受ける
port=$(jq -r '.services.ollama.command | .[index("--to") + 1]' <<<"$config")
port=${port##*:}
bind_host=$(jq -r '.services["open-webui"].ports[0].host_ip' <<<"$config")
# プロキシは host.docker.internal (ホストの loopback) へ転送するので、loopback を含む bind 先だけを受け付ける
case $bind_host in
127.* | ::1 | 0.0.0.0 | ::) ;;
*)
  echo "BIND_HOST=$bind_host is not supported with apps/text/compose.apple.yaml; use 127.0.0.1 or 0.0.0.0" >&2
  exit 1
  ;;
esac
# IPv6 のアドレスは、ポートと区別できるよう [] で囲む
if [[ $bind_host == *:* ]]; then
  bind_host="[$bind_host]"
fi
mkdir -p data/text/ollama/models data/text/ollama/home
# ollama.com の認証鍵は $HOME/.ollama から読まれるので、ホストのユーザーのサインイン状態を引き継がないよう、
# コンテナの ollama と同じくプロジェクトの下に分ける
export HOME="$PWD/data/text/ollama/home"
# コンテナの ollama と同じモデル置き場を使い、ollama-init がそこで digest を照合できるようにする
export OLLAMA_HOST="$bind_host:$port" OLLAMA_MODELS="$PWD/data/text/ollama/models"
export OLLAMA_KEEP_ALIVE OLLAMA_MAX_LOADED_MODELS
OLLAMA_KEEP_ALIVE=$(jq -r '.services.ollama.environment.OLLAMA_KEEP_ALIVE' <<<"$config")
OLLAMA_MAX_LOADED_MODELS=$(jq -r '.services.ollama.environment.OLLAMA_MAX_LOADED_MODELS' <<<"$config")
exec ollama serve
