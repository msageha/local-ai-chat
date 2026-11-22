#!/usr/bin/env bash
# text アプリの Open WebUI の画像生成を、image アプリの ComfyUI と open-webui.json の workflow につなぐ。
# Open WebUI は画像生成の設定を DB に保存し、環境変数を初回の起動時にしか読まないので、起動中の Open WebUI の API で書き換える。
# 画像生成以外の設定 (画像の編集など) は今の値のまま送り返す
set -euo pipefail

CDPATH='' cd -- "$(dirname "$0")/../.."
# 資格情報は、起動中の text アプリの open-webui が実際に公開しているアドレスにだけ送る
base=$(scripts/app-url.sh text)
api="$base/api/v1"

# 資格情報を平文の HTTP で送るので、ユーザーの .curlrc (-q) や proxy の設定を使わず、Open WebUI へ直接つなぐ
local_curl() { curl -q --noproxy '*' -fsS --max-time 30 "$@"; }

# 認証の有無は、compose の設定ではなく、起動中の Open WebUI 自身に問い合わせる
config=$(local_curl "$base/api/config")
# 応答が JSON のオブジェクト 1 個で、features.auth が boolean のときだけ続ける (false も -e で通るよう文字列にする)
if ! auth=$(jq -ers 'if length == 1 then .[0].features.auth else error("not a single JSON value") end
  | if type == "boolean" then tostring else error("not a boolean") end' <<<"$config" 2>/dev/null); then
  echo "cannot tell whether Open WebUI requires login: $base/api/config has no boolean features.auth" >&2
  exit 1
fi
if [[ $auth == true ]]; then
  IFS= read -rp "Email of an Open WebUI admin: " email
  IFS= read -rsp "Password: " password
  echo
  # パスワードをコマンドの引数に載せず (ps から見えるため)、標準入力で JSON にする
  credentials=$(printf '%s\n%s' "$email" "$password" | jq -Rn '[inputs] | {email: .[0], password: .[1]}')
else
  # 認証を無効にした Open WebUI は、資格情報を照合せずに管理者 (admin@localhost) の token を返す
  credentials='{"email": "", "password": ""}'
fi
token=$(local_curl -X POST "$api/auths/signin" -H 'Content-Type: application/json' --data-binary @- <<<"$credentials" | jq -er '.token')
# token もコマンドの引数に載せず、process substitution で header として渡す
auth_header() { printf 'Authorization: Bearer %s\n' "$token"; }

current=$(local_curl "$api/images/config" -H @<(auth_header))
# 前の接続先の API キーを、認証の無い ComfyUI へ送らないよう消す
desired=$(jq -c '{
  ENABLE_IMAGE_GENERATION: true,
  IMAGE_GENERATION_ENGINE: "comfyui",
  COMFYUI_BASE_URL: "http://comfyui:8188",
  COMFYUI_API_KEY: "",
  COMFYUI_WORKFLOW: (.workflow | tojson),
  COMFYUI_WORKFLOW_NODES: .nodes,
  IMAGE_SIZE: .size
}' apps/image/open-webui.json)
# workflow は大きくなりうるので、コマンドの引数の長さの上限に当たらないよう、jq には引数ではなくファイルとして渡す
updated=$(jq --slurpfile desired <(printf '%s' "$desired") '. + $desired[0]' <<<"$current" \
  | local_curl -X POST "$api/images/config/update" -H 'Content-Type: application/json' -H @<(auth_header) --data-binary @-)
# Open WebUI は知らないキーを黙って無視するので、版の更新でキー名が変わっても成功に見えないよう、保存された値を照合する
if ! jq -e --slurpfile desired <(printf '%s' "$desired") '. as $stored | $desired[0] | to_entries | all(.value == $stored[.key])' <<<"$updated" >/dev/null; then
  echo "Open WebUI did not store the image generation settings; check that its images config API still accepts these keys: $(jq -r 'keys | join(" ")' <<<"$desired")" >&2
  exit 1
fi
echo "connected Open WebUI image generation to the image app (http://comfyui:8188)"
