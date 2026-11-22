#!/usr/bin/env bash
# Apple Silicon の構成で、image か video のアプリの ComfyUI をホストで起動する (コンテナからは Metal を使えないため)。
# 初回と版を変えたときは ComfyUI と依存を data/<app>/comfyui-runtime に入れる。Ctrl-C で止める
set -euo pipefail

app=${1:?usage: serve.sh <image|video>}
CDPATH='' cd -- "$(dirname "$0")/../../.."
if [[ $(uname -sm) != "Darwin arm64" ]]; then
  echo "serve runs ComfyUI on the host and needs macOS on Apple Silicon" >&2
  exit 1
fi
# [env] に書いた secret を、長く動き続けるホストの ComfyUI に引き継がせない
unset WEBUI_SECRET_KEY
# 版・bind 先・ポートは compose が決めた値を使い、コンテナで動かすときと揃える
config=$(docker compose -f "apps/$app/compose.yaml" config --format json)
version=$(jq -r '.services.comfyui.build.args.COMFYUI_VERSION' <<<"$config")
port=$(jq -r '.services.comfyui.ports[0].published' <<<"$config")
bind_host=$(jq -r '.services.comfyui.ports[0].host_ip' <<<"$config")
# image のアプリでは、Open WebUI へつなぐプロキシが host.docker.internal (ホストの loopback) へ転送するので、
# loopback を含む bind 先だけを受け付ける
if [[ $app == image ]]; then
  case $bind_host in
  127.* | ::1 | 0.0.0.0 | ::) ;;
  *)
    echo "BIND_HOST=$bind_host is not supported with apps/image/compose.apple.yaml; use 127.0.0.1 or 0.0.0.0" >&2
    exit 1
    ;;
  esac
fi

# アプリごとに入れ、image と video を同時に起動しても入れ替えが衝突しないようにする
# 絶対パスで起動し、scripts/app-url.sh がこの checkout のプロセスを見分けられるようにする
root="$PWD/data/$app/comfyui-runtime"
install_dir="$root/app"
mkdir -p "$root"
if [[ $(cat "$install_dir/.version" 2>/dev/null) != "$version" ]]; then
  echo "installing ComfyUI $version into $install_dir"
  staging=$(mktemp -d "$root/app.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  # 1 分間 100KB/s を下回るか、10 分を超えたら打ち切る
  curl -fsSL --connect-timeout 30 --max-time 600 --speed-limit 102400 --speed-time 60 "https://github.com/Comfy-Org/ComfyUI/archive/refs/tags/$version.tar.gz" | tar -xz -C "$staging" --strip-components 1
  echo "$version" >"$staging/.version"
  rm -rf "$install_dir"
  mv "$staging" "$install_dir"
  trap - EXIT
fi
if [[ ! -x $root/venv/bin/python ]]; then
  uv venv --python 3.13 "$root/venv"
fi
# 依存が揃っていれば何も入れずに終わる。PyPI の macOS 向けの torch は Metal (MPS) を使える
uv pip install --python "$root/venv/bin/python" torch torchvision torchaudio -r "$install_dir/requirements.txt"

# ComfyUI は base directory の下の custom_nodes を作らずに読み、無いと起動に失敗する (v0.46.0 で確認)
mkdir -p "$PWD/data/$app/comfyui/custom_nodes"
exec "$root/venv/bin/python" "$install_dir/main.py" --listen "$bind_host" --port "$port" --disable-auto-launch --base-directory "$PWD/data/$app/comfyui"
