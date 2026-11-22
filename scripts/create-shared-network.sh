#!/usr/bin/env bash
# アプリの間をつなぐ network (local-ai-chat) を、無ければ作る。どの project にも属さない external の network なので、Compose は作らない。
# 同時に起動した別のアプリが先に作っていたら、それを使う
set -euo pipefail

docker network inspect local-ai-chat >/dev/null 2>&1 \
  || docker network create local-ai-chat >/dev/null \
  || docker network inspect local-ai-chat >/dev/null
