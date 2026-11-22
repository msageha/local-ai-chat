#!/usr/bin/env bash
# 起動中の text アプリと同じ compose ファイル (`mise run up text [gpu|apple]` で選んだもの) で docker compose を実行する。
# 構成ごとにサービスの定義 (ollama-init の環境変数など) が違うので、起動中の構成に合わせる。
# 呼び出すタスクは起動中の ollama を使う (`run --no-deps`) ので、アプリが動いていないときと、
# ほかの checkout から起動されたときは実行せずに止める。
set -euo pipefail

project=$(docker compose -f apps/text/compose.yaml config --format json | jq -r '.name')
# 今の組み合わせは ollama コンテナのラベルから読む。ollama は構成ごとにサービス定義が違い、構成を切り替えると必ず作り直されるため。
# `docker compose ls` の ConfigFiles は、作り直されずに残ったほかのサービスの古い組み合わせも合わせて返す
config_files=$(docker ps \
  --filter "label=com.docker.compose.project=$project" \
  --filter label=com.docker.compose.service=ollama \
  --filter label=com.docker.compose.oneoff=False \
  --format '{{.Label "com.docker.compose.project.config_files"}}')
case $config_files in
"$PWD/apps/text/compose.yaml") files=(-f apps/text/compose.yaml) ;;
"$PWD/apps/text/compose.yaml,$PWD/apps/text/compose.gpu.yaml") files=(-f apps/text/compose.yaml -f apps/text/compose.gpu.yaml) ;;
"$PWD/apps/text/compose.yaml,$PWD/apps/text/compose.apple.yaml") files=(-f apps/text/compose.yaml -f apps/text/compose.apple.yaml) ;;
"")
  echo "$project is not running; start it with 'mise run up text [gpu|apple]' first" >&2
  exit 1
  ;;
*)
  echo "$project was started with other compose files ($config_files); run 'mise run down text' in that checkout first" >&2
  exit 1
  ;;
esac
exec docker compose "${files[@]}" "$@"
