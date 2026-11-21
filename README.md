# local-ai-chat

ローカルで動作する AI チャット環境。ChatGPT 風 Web UI と Claude Code / Codex 風 CLI を Docker Compose で一括起動します。

## サービス構成

| サービス      | 説明                                                                                       | デフォルトポート |
| ------------- | ------------------------------------------------------------------------------------------ | ---------------- |
| `ollama`      | LLM バックエンド (OpenAI 互換 API)                                                         | 11434            |
| `ollama-init` | 起動時に `ollama/models.txt` のモデルを pull し、digest が一致したものにエイリアスを付ける | — (完了後に終了) |
| `open-webui`  | ChatGPT 風 Web UI                                                                          | 3000             |
| `cli`         | aider ベースの Claude Code / Codex 風 CLI                                                  | — (対話型)       |

## 使い方

前提: Docker Compose v2 と [mise](https://mise.jdx.dev/)。NVIDIA GPU を使う場合は NVIDIA Container Toolkit も必要です。
macOS の Docker Desktop からは GPU (Metal) を使えないため、Ollama は CPU で動作します。

```sh
mise trust && mise install   # 初回のみ: ツールの導入と pre-commit hook の設定
cp .env.example .env         # 必要ならポート・既定モデル・GPU 構成 (COMPOSE_FILE) を変更
mise run up                  # 起動。モデルの pull はバックグラウンドで進む
mise run ui                  # ブラウザで Web UI を開く
```

モデルの pull 状況は `mise run logs` で確認できます。pull が終わったモデルから順に Web UI に現れます。
既定ではポートを `127.0.0.1` にのみ bind します。同じネットワークの他の端末から使うなら `.env` で `BIND_HOST=0.0.0.0` を設定してください。
CLI で別のプロジェクトを編集するときは `MOUNT_DIR=/path/to/project mise run code` のようにマウント先を指定します。

### モデルの追加・変更

`ollama/models.txt` に 1 行 `<alias> <source>` で追記し、`mise run digests` で digest を書き込んでから `mise run pull` を実行します。
source は `registry.ollama.ai/<namespace>/<model>:<tag>` (公式モデルの namespace は `library`) か `hf.co/<user>/<repo>:<tag>` の形で書きます。
digest は manifest の sha256 で、`mise run models` が表示する ID はその先頭 12 文字です。
Ollama は digest を指定して pull できないため、tag で pull した後に digest を照合し、一致したときだけ alias を更新します。
tag の内容が上流で更新されると、Renovate が digest を更新するまで (「[依存関係の更新](#依存関係の更新)」) そのモデルは digest 不一致で失敗し、alias は前の版のまま残ります。
alias は Ollama 上で `<alias>:latest` として登録され、Web UI と CLI から参照できます。CLI のモデルはシェルの環境変数で切り替えます (`MODEL=weirdcompound mise run chat`。`.env` の `DEFAULT_MODEL` は既定値、`MODEL` は `.env` では効きません)。
pull や照合に失敗したモデルは警告を出してスキップされ、最後に非 0 で終了します。

## 開発

`mise install` が `prek install` を実行し、`.pre-commit-config.yaml` の hook を commit 時に走らせます。pre-commit では dprint による整形、TOML の構文検査、shellcheck、actionlint と zizmor による workflow の検査、dclint と `docker compose config` による compose ファイルの検査、typos によるスペルチェック、タスク一覧の同期、gitleaks による staged 差分のシークレットスキャンを行い、commit-msg では commitlint が commit message を [Conventional Commits](https://www.conventionalcommits.org/) で検査します。compose ファイルの検証には Docker CLI が必要です。
手元で全ファイルを検査するには `mise exec -- prek run --all-files` を実行します。
CI (`.github/workflows/ci.yaml`) は pull request で、同じ hook を全ファイルに対して実行する `prek` job と、コミット履歴全体をスキャンする `gitleaks` job を走らせます。
issue や PR のコメントで `@claude` とメンションすると Claude Code が応答し (`claude.yaml`)、毎週月曜には前回以降の差分を Claude Code がレビューして指摘を issue に起票します (`claude-sweep.yaml`)。どちらもリポジトリ secret `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token` で発行) が必要で、`@claude` への応答には [Claude GitHub App](https://github.com/apps/claude) のインストールも必要です。
共通ファイルは [dope-corp/template](https://github.com/dope-corp/template) に揃えており、`mise run template-diff` で差分を確認できます。

### 依存関係の更新

ツール・イメージ・モデルはすべて digest か exact version で固定し、Renovate が毎週月曜 9 時前 (Asia/Tokyo) に更新 PR を作ります。

- `mise.toml` のツールと `mise.lock`、`compose.yaml` のイメージ (`<tag>@sha256:<digest>`)、workflow の `uses:` の commit SHA、`.pre-commit-config.yaml` の hook、`dprint.json` の plugin
- `ollama/models.txt` のモデルの digest: Ollama 形式のレジストリは manifest の digest を返さないため、`ollama-models.yaml` が毎日 0 時 (Asia/Tokyo) に各 tag が今指す manifest の sha256 を計算して `ollama-digests` ブランチの `digests.json` に置き、Renovate がそれを読んで更新する。モデルを追加してから最初の計算までは、Renovate の Dependency Dashboard に digest を決められない旨の警告が出る

major 以外の更新は 1 つの PR にまとめ、GitHub の auto-merge で merge します。main の ruleset が CI の `prek` / `gitleaks` の成功を必須にしているので、CI が通るまで merge されません。
Renovate は公開から 7 日経っていない版を待ってから取り込みます (`minimumReleaseAge`)。ただし、公開日時を取得できないもの (ghcr.io のイメージ、tag が付け替えられた action の digest、モデルの digest、`mise.lock` の再生成) は待たずに取り込みます。
major の更新は個別の PR になり、手で確認して merge します。

## 収録モデル

> **ローカル運用のコンセプト:** Claude Code / Codex では安全フィルターにより拒否されるタスク（セキュリティ研究・exploit 分析・センシティブな創作など）を担うため、拒否を減らしたモデル (重みから拒否の方向を取り除いた abliterated と、追加学習や merge による uncensored) を中心に収録しています。

### 選定基準

用途ごとに、[UGI Leaderboard](https://huggingface.co/spaces/DontPlanToEnd/UGI-Leaderboard) で用途に対応する指標が最も高いモデルを、想定するマシンに載るサイズの中から選んでいます。UGI Leaderboard は uncensored モデルを、拒否せずに答える度合い (W/10)、センシティブな話題の知識 (UGI)、一般的な知識・知能 (NatInt) などで比べるベンチマークです。W/10 が 8 未満 (拒否が多い) のモデルは候補から外しています。順位は 2026-10-17 更新のデータ ([ugi-leaderboard-data.csv](https://huggingface.co/spaces/DontPlanToEnd/UGI-Leaderboard/blob/91957a6e66771c651b0c9e472f415cf078091c06/ugi-leaderboard-data.csv)) によるもので、データが更新されると変わりえます。サイズの上限は総パラメータ数 (CSV の `Total Parameters`。MoE も実効パラメータ数ではなく総数) で判定します。

| 用途                           | 比べる指標                                                                        | サイズの上限 |
| ------------------------------ | --------------------------------------------------------------------------------- | ------------ |
| 汎用・セキュリティ             | UGI (センシティブな話題の知識) と Hazardous (そのうち LLM が通常は手伝わない話題) | 36B          |
| 医療・薬学・法律などの専門知識 | Textbook (事実・統計・数学・論理の一般知識。専門分野の正確性は測っていない)       | 36B          |
| 創作・ロールプレイ             | Writing                                                                           | 36B          |
| 推論                           | NatInt (知能の総合)                                                               | 10B          |
| 軽量・デイリーユース           | UGI (センシティブな話題の知識)                                                    | 10B          |
| コーディング・エージェント     | Qwen3.8-27B 公式のベンチマーク (SWE-bench Pro・LiveCodeBench)                     | 36B          |
| 最も性能の高い abliterated     | NatInt (知能の総合)。36B 以下と 125B 以下で 1 つずつ                              | 36B / 125B   |
| 最も性能の高い uncensored      | NatInt (知能の総合)。36B 以下と 125B 以下で 1 つずつ                              | 36B / 125B   |
| 262,144 トークンを超える長文   | なし (収録モデルで唯一 10M の上限を持つ Llama 4 Scout を置いている)               | —            |

UGI Leaderboard は 1 つのモデルを thinking の有無で別の行として計測しているので、Ollama で既定のまま使ったときの状態に合う行で比べています。既定の状態は GGUF に埋め込まれた chat template で決まり、Qwen3.5 系は thinking が有効 (thinking 有りの行を使う)、Gemma 4 系は無効 (thinking 無しの行を使う) です。thinking の有無で行が分かれていないモデルは、その 1 行を使います。
画像入力は UGI Leaderboard では測っていないので、projector を同梱して画像を受け付けるモデルを用途の欄に挙げています。
abliterated は、拒否に関わる方向を重みから取り除いたモデル (Heretic・Derestricted など) を、uncensored は追加学習や merge で拒否を減らしたモデルを指します。配布元のモデルカードかタグに abliteration (Heretic・Derestricted を含む) で処理したとあれば、`uncensored` のタグが併記されていても abliterated に分類します。1 位が同点のときと、汎用のように 2 つの指標を使う枠で 1 位が分かれたときは UGI が高い方を、UGI も同じなら NatInt が高い方を選びます。125B 以下の枠で 1 位が 36B 以下の枠と同じモデルになるときは、36B を超えるモデルの中の 1 位を選びます。uncensored の 36B 以下の 1 位は `qwen35-queen` なので、この枠は汎用と兼ねています。
UGI Leaderboard はコーディングを測っておらず、Qwen3.8 系もまだ計測していないため、コーディングには公式の値で前世代を上回る `qwen38` を置いています。また、`llama4` は拒否を減らす処理をしていない公式モデル (W/10 5.2) ですが、262,144 トークンを超える長文を扱える代わりのモデルが無いので、W/10 の条件の例外として置いています。
モデルを入れ替えるときは、この表の指標と、上に書いた条件 (サイズの上限・W/10・thinking の扱い・分類) で比べ直し、Ollama で pull できる GGUF (単一ファイル) があるものから選びます。

### モデル一覧

| エイリアス                  | ベースモデル                   | アーキテクチャ                      | コンテキスト | サイズ | 主な用途                                   | 推奨マシン                          |
| --------------------------- | ------------------------------ | ----------------------------------- | ------------ | ------ | ------------------------------------------ | ----------------------------------- |
| `qwen35-queen:latest`       | Alibaba Qwen3.5 27B            | Dense 27B                           | 256K         | ~17GB  | 汎用・セキュリティ・CTF・exploit・画像入力 | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `qwen35-27b-heretic:latest` | Alibaba Qwen3.5 27B            | Dense 27B                           | 256K         | ~17GB  | 医療・薬学・法律などの専門知識・画像入力   | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `weirdcompound:latest`      | Mistral Small 3.2 24B の merge | Dense 24B                           | 128K         | ~14GB  | 創作・フィクション・ロールプレイ           | Apple Silicon 32GB+ / NVIDIA 16GB+  |
| `qwen35-9b-heretic:latest`  | Alibaba Qwen3.5 9B             | Dense 9B                            | 256K         | ~6GB   | 推論・脅威分析・ロジック問題・画像入力     | Apple Silicon 16GB+ / NVIDIA 8GB+   |
| `qwen35-4b-heretic:latest`  | Alibaba Qwen3.5 4B             | Dense 4B                            | 256K         | ~3GB   | 軽量汎用・デイリーユース・画像入力         | Apple Silicon 8GB+ / NVIDIA 6GB+    |
| `qwen38:latest`             | Alibaba Qwen3.8 27B            | Dense 27B                           | 256K         | ~19GB  | コーディング・エージェント                 | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `gemma4-heretic:latest`     | Google Gemma 4 31B             | Dense 31B                           | 256K         | ~19GB  | 最も性能の高い abliterated (36B 以下)      | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `assistant-pepe:latest`     | Meta Llama 3.1 70B             | Dense 70B                           | 128K         | ~43GB  | 最も性能の高い uncensored (125B 以下)      | Apple Silicon 64GB+ / NVIDIA 48GB+  |
| `xortron-large:latest`      | Mistral Large 2411 123B        | Dense 123B                          | 128K         | ~73GB  | 最も性能の高い abliterated (125B 以下)     | Apple Silicon 128GB+ / NVIDIA 96GB+ |
| `llama4:latest`             | Meta Llama 4 Scout             | MoE (総109B / 実効17B / 16 experts) | 10M          | ~67GB  | 262,144 トークンを超える長文、画像入力     | Apple Silicon 96GB+ / NVIDIA 80GB+  |

サイズは Q4 量子化時のダウンロード容量 (画像入力用の projector を含む) で、起動時に全モデルを pull するのに合計約 280GB のディスクを使います。pull は `ollama/models.txt` の上から順に進み、既定モデルの `qwen35-4b-heretic` を先頭に置いています。実行時はサイズに KV cache 分のメモリが加わります。
推奨マシンは、Apple Silicon はホストの搭載メモリ、NVIDIA は GPU の VRAM の目安です。Ollama はコンテナで動くので、Docker Desktop の VM にもサイズと KV cache が収まるメモリを割り当てる必要があります (Docker Desktop の既定はホストの 50%)。

### モデルの使い分け

```
どれを使えばいいかわからない場合
├── 軽い・速いほうがいい            → qwen35-4b-heretic
├── 何でもこなしたい（汎用）        → qwen35-queen
├── セキュリティ・CTF・exploit      → qwen35-queen
├── 医療・薬学・法律の詳細情報     → qwen35-27b-heretic (一般知識の指標で選定。専門分野の正確性は未評価)
├── 小説・RP・NSFW コンテンツ      → weirdcompound
├── 推論が必要な問題（軽量）       → qwen35-9b-heretic
├── コーディング・エージェント     → qwen38 (CLI では `MODEL=qwen38 mise run code`)
├── 性能重視 (abliterated)          → gemma4-heretic / xortron-large (大型)
├── 性能重視 (uncensored)           → qwen35-queen / assistant-pepe (大型)
├── 画像入力                       → qwen35-queen / qwen35-*-heretic
└── 262,144 トークンを超える長文 → llama4
```

---

### モデル詳細

エイリアスの `heretic` は、拒否に関わる方向を重みから取り除く (abliteration) ツール Heretic で処理したモデルを指します。Qwen3.5 系は GGUF に埋め込まれた chat template の既定で thinking が有効になり、Ollama の `think` で切り替えます。

#### `qwen35-queen:latest`

- **Ollamaタグ:** `hf.co/mradermacher/Qwen3.5-Queen-27B-GGUF:Q4_K_M`
- **特徴:** `Qwen/Qwen3.5-27B` を aifeifei798 が追加学習したもの。abliteration ではなく学習で拒否を減らしており、配布元はロールプレイと複数の persona を演じることを特徴に挙げている。36B 以下で UGI が最も高く、Hazardous も 1 位タイ。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `qwen35-27b-heretic:latest`

- **Ollamaタグ:** `hf.co/llmfan46/Qwen3.5-27B-uncensored-heretic-v1-GGUF:Q4_K_M`
- **特徴:** Qwen3.5 27B を Heretic で abliteration したもの (UGI Leaderboard 上の名前は `llmfan46/Qwen3.5-27B-heretic-v3`)。36B 以下で Textbook が最も高い。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `weirdcompound:latest`

- **Ollamaタグ:** `hf.co/mradermacher/WeirdCompound-v1.7-24b-GGUF:Q4_K_M`
- **特徴:** Mistral Small 3.2 24B 系の創作向けモデル (Cydonia など) を mergekit で合成したもの。36B 以下で Writing が最も高い。thinking を持たず、画像入力には対応しない。
- **ライセンス:** 配布元に表記なし (派生元の Mistral Small 3.2 は Apache 2.0)

#### `qwen35-9b-heretic:latest`

- **Ollamaタグ:** `hf.co/mradermacher/Qwen3.5-9B-heretic-v2-GGUF:Q4_K_M`
- **特徴:** Qwen3.5 9B を Heretic で abliteration したもの。10B 以下で NatInt が最も高い。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `qwen35-4b-heretic:latest`

- **Ollamaタグ:** `hf.co/mradermacher/Qwen3.5-4B-SOMPOA-heresy-v2-GGUF:Q4_K_M`
- **特徴:** Qwen3.5 4B を Heretic で abliteration したもの。10B 以下で UGI が最も高い。画像入力に対応。デフォルトモデル。
- **ライセンス:** Apache 2.0

#### `qwen38:latest`

- **Ollamaタグ:** `hf.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF:Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf`
- **特徴:** Qwen3.8 27B をベースに HauhauCS が拒否を減らした "Aggressive" 版（拒否率を最小化し直接的に回答。手法は配布元に記載が無い）。公式の Qwen3.8-27B は SWE-bench Pro 61.7・LiveCodeBench v6 90.3 で、Qwen3.6-27B (53.5・83.9) を上回る。imatrix を用いた独自 K_P 量子化（Q4_K_P, 18GB）で同サイズ標準量子化より品質劣化が小さい。GGUF に multi-token prediction (MTP) 用のヘッドを同梱。画像入力用の projector (mmproj) も一緒に pull されるが、画像入力の動作は未検証。
- **ライセンス:** Apache 2.0
- **備考:** K_P 量子化は Hugging Face の Ollama 互換エンドポイントが量子化名として認識しないため、tag には量子化名ではなく GGUF のファイル名を指定している。MTP ヘッドも非標準のため Ollama バージョンによっては読み込みに失敗することがあり、その場合は同世代の素の abliterated 版 `huihui_ai/Qwen3.8-abliterated:27b`（18GB）への差し替えを検討

#### `gemma4-heretic:latest`

- **Ollamaタグ:** `hf.co/mradermacher/gemma-4-31B-it-heretic-GGUF:Q4_K_M`
- **特徴:** `google/gemma-4-31B-it` を coder3101 が Heretic で abliteration したもの。36B 以下の abliterated で NatInt と UGI がともに最も高い。GGUF の chat template の既定で thinking は無効で、ここに挙げた順位は thinking 無しの行 (NatInt 35.64・UGI 56.38) による。UGI Leaderboard では、assistant の応答の先頭に思考の開始タグを入れて thinking させた計測で NatInt 36.53・UGI 65.69 になっているが、Ollama で thinking を有効にしたときに同じ値になるかは確かめていない。この GGUF には projector が無く、画像入力には対応しない。
- **ライセンス:** Apache 2.0

#### `assistant-pepe:latest`

- **Ollamaタグ:** `hf.co/SicariusSicariiStuff/Assistant_Pepe_70B_GGUF:Q4_K_M`
- **特徴:** `meta-llama/Llama-3.1-70B-Instruct` を SicariusSicariiStuff が 4chan のデータで追加学習したもの。125B 以下の uncensored で NatInt が最も高い。システムプロンプトが無くても使えるように学習されている。画像入力には対応しない。
- **ライセンス:** Llama 3.1 Community License

#### `xortron-large:latest`

- **Ollamaタグ:** `hf.co/mradermacher/XORTRON.CriminalComputing.LARGE.2026.3-GGUF:Q4_K_M`
- **特徴:** `mistralai/Mistral-Large-Instruct-2411` を darkc0de が Heretic で abliteration したもの。125B 以下で NatInt と UGI がともに最も高く、収録モデルのうち UGI Leaderboard で計測されたものの中でも最も高い。Dense 123B なので、同じメモリに載る MoE より生成は遅い。画像入力には対応しない。
- **ライセンス:** 配布元は WTFPL と表記 (派生元の Mistral Large 2411 は Mistral Research License)

#### `llama4:latest`

- **Ollamaタグ:** `llama4:17b-scout-16e-instruct-q4_K_M`
- **特徴:** Meta 公式の Llama 4 Scout。拒否を減らす処理はしていない。収録モデルで唯一 262,144 トークンを超えるコンテキスト (公称 10M トークン) を持つ。画像入力にも対応。総パラメータ 109B のため Q4 でも 67GB を要する。
- **ライセンス:** Llama 4 Community License
- **備考:** Ollama はリクエストで `num_ctx` を指定しないと、VRAM の量に応じて 4,096・32,768・262,144 トークンのいずれかのコンテキストで動かすので、それを超える入力には Ollama ネイティブ API (`/api/chat`) の `options.num_ctx` か、Web UI のチャットの詳細設定のコンテキスト長を指定する。OpenAI 互換 API (`/v1`) はこの指定を受け付けないので、`PARAMETER num_ctx` を書いた Modelfile で別のモデルを作る。長いコンテキストほど KV cache のメモリが増えるので、実際に扱える長さはマシンのメモリで決まる。

## タスク

タスクは `mise run <task>` で実行します。`mise.toml` の `[tasks]` を変更したら `mise run docs` で以下の一覧を更新します (pre-commit hook からも自動実行されます)。

<!-- dprint-ignore-start -->
<!-- mise-tasks -->
## `chat`

- **Usage:** `chat`

aider でチャットする (環境変数 MODEL にエイリアスを指定するとモデルを切り替えられる)

## `code`

- **Usage:** `code`

MOUNT_DIR のコードを aider で編集する (環境変数 MODEL でモデルを切り替え、`--` 以降は aider に渡す)

## `digests`

- **Usage:** `digests`

ollama/models.txt の digest を各 tag が今指す manifest に更新する (digest の無い行には追記する)

## `docs`

- **Usage:** `docs`

README.md のタスク一覧を mise.toml と同期する

## `down`

- **Usage:** `down`

全サービスを停止する

## `logs`

- **Usage:** `logs`

ログを追従表示する

## `models`

- **Usage:** `models`

Ollama に登録済みのモデルを一覧する

## `pull`

- **Usage:** `pull`

ollama/models.txt のモデルを pull してエイリアスを更新する

## `shell`

- **Usage:** `shell`

aider コンテナで bash を起動する

## `template-diff`

- **Usage:** `template-diff`

共通ファイルを dope-corp/template の main と比較する

## `ui`

- **Usage:** `ui`

Web UI をブラウザで開く

## `up`

- **Usage:** `up`

全サービスを起動する。モデルの pull はバックグラウンドで進む (`mise run logs` で確認)
<!-- /mise-tasks -->
<!-- dprint-ignore-end -->
