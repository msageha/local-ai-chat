#!/usr/bin/env bash
# この checkout から起動中のアプリの Web UI (text は Open WebUI、image と video は ComfyUI) の URL を出す。
# 起動中のコンテナが公開しているアドレスを使うので、設定を変えてまだコンテナを作り直していなくても、実際の接続先を指す。
# Apple Silicon の構成の ComfyUI はホスト (apps/shared/comfyui/serve.sh) で動いてコンテナがポートを公開しないので、
# そのプロセスの起動時の引数から読む
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

address=""
# Docker に問い合わせられなくても (Docker が止まっていても)、image と video ではホストの ComfyUI を探す
if project=$(docker compose -f "apps/$app/compose.yaml" config --format json | jq -er '.name'); then
  # 同じ project 名の別の checkout のコンテナを指さないよう、接続するコンテナそのものの起動元を照合する
  container=$(docker ps -q \
    --filter "label=com.docker.compose.project=$project" \
    --filter "label=com.docker.compose.service=$service" \
    --filter "label=com.docker.compose.project.working_dir=$PWD/apps/$app" | head -n 1) || true
  if [[ -n $container ]]; then
    address=$(docker port "$container" "$target" 2>/dev/null | head -n 1) || true
  fi
fi
if [[ -z $address && $app != text ]]; then
  # この checkout のホストの ComfyUI を、起動したときの引数 (パスはリテラルで照合する) で見つけ、実際の待ち受け先を読む
  main="$PWD/data/$app/comfyui-runtime/app/main.py"
  while read -r args; do
    if [[ $args == *" $main --listen "*" --port "* ]]; then
      listen=${args#*" --listen "}
      port=${args#*" --port "}
      address="${listen%% *}:${port%% *}"
      break
    fi
  # macOS の ps は C ロケールで非 ASCII の文字を加工して表示するので、パスと照合できるよう UTF-8 で出させる
  done < <(LC_ALL=en_US.UTF-8 ps -axo args=)
fi
if [[ -z $address ]]; then
  echo "$app is not running from this checkout; start it with 'mise run up $app <setup>' (and 'mise run serve $app' for apple) first" >&2
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
