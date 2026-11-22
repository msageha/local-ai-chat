#!/usr/bin/env bash
# この checkout のアプリの Web UI (text は Open WebUI、image と video は ComfyUI) の URL を出す。
# コンテナが動いていれば、そのコンテナが実際に公開しているアドレスを使う (設定を変えてまだ作り直していなくても実際の接続先を指す)。
# Apple Silicon の構成の ComfyUI はホスト (apps/shared/comfyui/serve.sh) で動いてコンテナがポートを公開しないので、
# serve.sh と同じく compose の設定から待ち受け先を求める (応答するかは呼び出し元が確かめる)
set -euo pipefail

app=${1:?usage: app-url.sh <text|image|video>}
CDPATH='' cd -- "$(dirname "$0")/.."
case $app in
text) service=open-webui target=8080 ;;
image | video) service=comfyui target=8188 ;;
*)
  echo "unknown app: $app" >&2
  exit 1
  ;;
esac

config=$(docker compose -f "apps/$app/compose.yaml" config --format json)
project=$(jq -er '.name' <<<"$config")
# 同じ project 名の別の checkout のコンテナを指さないよう、接続するコンテナそのものの起動元を照合する
container=$(docker ps -q \
  --filter "label=com.docker.compose.project=$project" \
  --filter "label=com.docker.compose.service=$service" \
  --filter "label=com.docker.compose.project.working_dir=$PWD/apps/$app" | head -n 1) || true
address=""
if [[ -n $container ]]; then
  address=$(docker port "$container" "$target" 2>/dev/null | head -n 1) || true
fi
if [[ -z $address && $app != text ]]; then
  address=$(jq -er '.services.comfyui.ports[0] | "\(.host_ip):\(.published)"' <<<"$config")
fi
if [[ -z $address ]]; then
  echo "$app is not running from this checkout; start it with 'mise run up $app <setup>' first" >&2
  exit 1
fi
host=${address%:*}
port=${address##*:}
# 全アドレスで待ち受けているときは、同じアドレスファミリーの loopback へつなぐ (localhost は IPv6 を先に試すことがあり、別のサービスに当たりうる)
case $host in
0.0.0.0) host=127.0.0.1 ;;
'[::]' | ::) host='[::1]' ;;
\[*) ;;
*:*) host="[$host]" ;;
esac
echo "http://$host:$port"
