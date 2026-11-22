#!/bin/sh
# models.txt の各ファイルを Hugging Face から commit を固定して取得し、sha256 が一致したものだけを
# ComfyUI のモデル置き場 (<models-dir>/<directory>/<file>) に置く。
# 一部のファイルが失敗しても残りを処理し、失敗があれば最後に非 0 で終了する。
set -u

models_file=${1:?usage: pull-models.sh <models.txt> <models-dir>}
models_dir=${2:?usage: pull-models.sh <models.txt> <models-dir>}
if [ ! -r "$models_file" ]; then
  echo "ERROR: cannot read models file: $models_file" >&2
  exit 1
fi
failed=""
seen=""
# 同じアプリの取得 (起動時と `mise run pull <app>`) が並んで走ると、同じ .part に書き込み合うので、置き場ごとに 1 つずつ動かす
mkdir -p "$models_dir"
exec 9>"$models_dir/.pull-models.lock"
if ! flock -n 9; then
  echo "waiting for another pull into $models_dir to finish"
  if ! flock 9; then
    echo "ERROR: cannot lock $models_dir/.pull-models.lock" >&2
    exit 1
  fi
fi

while read -r directory repo revision path sha256 _ || [ -n "$directory" ]; do
  case $directory in '' | '#'*) continue ;; esac
  file=${path##*/}
  # revision は commit の SHA に限る (branch や tag は指す先が変わるため)。path はそのまま URL に入れるので、
  # URL で別の意味を持つ # ? % を含む行は受け付けない
  if ! printf '%s\n' "$directory" | grep -qx '[a-z0-9_]\{1,\}' \
    || ! printf '%s\n' "$repo" | grep -qx '[A-Za-z0-9._-]\{1,\}/[A-Za-z0-9._-]\{1,\}' \
    || ! printf '%s\n' "$revision" | grep -qx '[0-9a-f]\{40\}' \
    || ! printf '%s\n' "$sha256" | grep -qx '[0-9a-f]\{64\}' \
    || [ -z "$file" ] || [ "$file" = .. ] \
    || case $path in *'#'* | *'?'* | *'%'*) true ;; *) false ;; esac; then
    echo "WARNING: skipping malformed line (expected '<directory> <owner>/<repo> <commit sha> <path> <sha256>'): $directory $repo $path" >&2
    failed="$failed $path"
    continue
  fi
  dest="$models_dir/$directory/$file"
  # 同じ保存先を指す行が複数あると互いに上書きし合うので、2 行目以降は取得せずに失敗とする
  case " $seen " in *" $directory/$file "*)
    echo "WARNING: skipping duplicate destination $directory/$file: $repo $path" >&2
    failed="$failed $directory/$file"
    continue
    ;;
  esac
  seen="$seen $directory/$file"
  # 中断した取得は途中のファイルから再開する。途中のファイルは版 (sha256) ごとに分け、別の版の途中から再開しないよう、
  # ほかの版の途中のファイルは消す (取得済みの版に戻したときも、数 GB の途中のファイルを残さない)
  part="$dest.$sha256.part"
  for stale in "$dest".*.part; do
    [ "$stale" = "$part" ] || rm -f "$stale"
  done
  # 照合した sha256 を隣のファイルに残し、同じ版なら取得も照合もし直さない (数 GB のファイルを起動のたびにハッシュしないため)。
  # ComfyUI は拡張子でモデルを選ぶので、.sha256 と取得中の .part はモデルの一覧に出ない
  if [ -f "$dest" ] && [ "$(cat "$dest.sha256" 2>/dev/null)" = "$sha256" ]; then
    echo "ready: $directory/$file"
    continue
  fi
  mkdir -p "$models_dir/$directory"
  echo "pulling: $directory/$file ($repo@$revision)"
  # 5 分間 100KB/s を下回るか、リトライを含めて 2 時間を超えたら打ち切る (curl の --max-time は 1 回の転送ごとにしか効かない)。
  # 打ち切っても、次の取得で途中のファイルから続きを取る
  # -g: ファイル名の [] や {} を curl の URL の glob として解釈させない
  if ! timeout 7200 curl -gfL --retry 3 --connect-timeout 30 --speed-limit 102400 --speed-time 300 -C - -o "$part" \
    "https://huggingface.co/$repo/resolve/$revision/$path"; then
    echo "WARNING: failed to download $directory/$file" >&2
    failed="$failed $directory/$file"
    continue
  fi
  actual=$(sha256sum "$part" | cut -d ' ' -f 1)
  if [ "$actual" != "$sha256" ]; then
    echo "WARNING: sha256 mismatch for $directory/$file: expected $sha256, got $actual" >&2
    rm -f "$part"
    failed="$failed $directory/$file"
    continue
  fi
  # 置き換えの途中で止まっても、古い版の照合の記録で新しい版を ready と判定しないよう、先に記録を消す
  if ! rm -f "$dest.sha256" || ! mv "$part" "$dest" || ! printf '%s\n' "$sha256" > "$dest.sha256"; then
    echo "WARNING: failed to place $directory/$file" >&2
    failed="$failed $directory/$file"
    continue
  fi
  echo "ready: $directory/$file"
done < "$models_file"

if [ -n "$failed" ]; then
  echo "ERROR: failed to prepare:$failed" >&2
  exit 1
fi
