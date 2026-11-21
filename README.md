# local-ai-chat

ローカルで動作する AI チャット環境。ChatGPT 風 Web UI と Claude Code / Codex 風 CLI を Docker Compose で一括起動します。

## サービス構成

| サービス      | 説明                                                                                                   | デフォルトポート |
| ------------- | ------------------------------------------------------------------------------------------------------ | ---------------- |
| `ollama`      | LLM バックエンド (OpenAI 互換 API)。Apple Silicon の構成では、ホストの Ollama へ転送するプロキシになる | 11434            |
| `ollama-init` | 起動時に `ollama/models.txt` のモデルを pull し、digest が一致したものにエイリアスを付ける             | — (完了後に終了) |
| `open-webui`  | ChatGPT 風 Web UI                                                                                      | 3000             |
| `cli`         | aider ベースの Claude Code / Codex 風 CLI                                                              | — (対話型)       |

## 使い方

前提: Docker Compose v2 と [mise](https://mise.jdx.dev/)。NVIDIA GPU を使う場合は NVIDIA Container Toolkit も必要です。
macOS の Docker のコンテナからは GPU (Metal) を使えないため、Apple Silicon の Mac では「[Apple Silicon の構成](#apple-silicon-の構成)」で Ollama をホストで動かすと GPU を使えます。

```sh
mise trust && mise install   # 初回のみ: ツールの導入と pre-commit hook の設定
cp .env.example .env         # 必要ならポート・既定モデル・GPU 構成 (COMPOSE_FILE) を変更
mise run up                  # 起動。モデルの pull はバックグラウンドで進む (全モデルで約 360GB。「収録モデル」を参照)
mise run ui                  # ブラウザで Web UI を開く
```

モデルの pull 状況は `mise run logs` で確認できます。pull が終わったモデルから順に Web UI に現れます。
既定ではポートを `127.0.0.1` にのみ bind します。同じネットワークの他の端末から使うなら `.env` で `BIND_HOST=0.0.0.0` を設定してください。
CLI で別のプロジェクトを編集するときは `MOUNT_DIR=/path/to/project mise run code` のようにマウント先を指定します。

### Apple Silicon の構成

Apple Silicon の Mac では、Ollama をコンテナではなくホストで動かします。ホストの Ollama は GPU (Metal) で推論し、Ollama の library に MLX 形式の tag しか無いモデル (`ollama/models.txt` で `mlx` を付けた行) も pull して使えます。

前提は次のとおりです。`docker compose -f compose.yaml -f compose.apple.yaml config --quiet` がエラーなく終われば、Compose の条件は満たしています。

- macOS 14 以降 (ホストの Ollama の要件)
- compose ファイルの `!reset` タグに対応した Docker Compose
- コンテナから `host.docker.internal` でホストに届く Docker (Docker Desktop・OrbStack)
- `.env` の `BIND_HOST` が `127.0.0.1` か `0.0.0.0` (ホストの Ollama もここで待ち受け、コンテナからはホストの loopback 経由で接続するため)
- Ollama.app など、ほかの Ollama が `OLLAMA_PORT` (既定 11434) で動いていないこと (動いていると、その Ollama に接続してしまう)

通常の構成から切り替えるときは、`mise run down` で止めてから `.env` で `COMPOSE_FILE=compose.yaml:compose.apple.yaml` を設定し、ホストの Ollama が待ち受けを始めたのを確かめてから全体を起動します。

```sh
mise run serve              # ホストの Ollama を起動する (このターミナルで動き続ける。"Listening on" と出れば起動済み)
mise run up                 # 別のターミナルで起動。以降の操作は通常と同じ
```

止めるときは `mise run down` でコンテナを止め、`mise run serve` のターミナルで Ctrl-C を押します。通常の構成に戻すときは、両方を止めてから `.env` の `COMPOSE_FILE` を戻します。

ホストの Ollama は `mise install` が入れる版 (コンテナのイメージと同じ版) で、モデルはコンテナのときと同じ `data/ollama/models` に、ollama.com の認証鍵は `data/ollama/home` に置きます (ホストのユーザーのサインイン状態は使わない)。`ollama` サービスはホストの Ollama へ (`host.docker.internal` 経由で) 転送するプロキシになるので、Web UI・CLI・モデルの pull の接続先は通常の構成と変わりません。
この構成以外では、`mlx` を付けたモデルは pull せずに飛ばします。ただし、この構成で pull した後に同じ Mac で通常の構成へ戻すと、登録は残って選択肢に出ますが動きません。使わないなら `ollama rm <alias> <source>` (例: `docker compose exec ollama ollama rm inkling2-mini inkling-2-mini:26b-a5b-nvfp4`) で消してください。

### モデルの追加・変更

`ollama/models.txt` に 1 行 `<alias> <source>` (Ollama の library に MLX 形式の tag しか無いモデルは `<alias> <source> mlx`) で追記し、`mise run digests` で digest を書き込んでから `mise run pull` を実行します。
source は `registry.ollama.ai/<namespace>/<model>:<tag>` (公式モデルの namespace は `library`) か `hf.co/<user>/<repo>:<tag>` の形で書きます。
tag は単体の manifest を返すものに限ります。また、`registry.ollama.ai/library/<model>:latest` (`ollama.com/library/` も同じ) は alias (`<alias>:latest`) と同じ名前空間に入って alias を上書きしうるので、`latest` 以外の tag を指定します。digest の照合は単体の manifest を前提にしているので、manifest list (複数の版を束ねた一覧) を返す tag は扱えません。
digest は manifest の sha256 で、`mise run models` が表示する ID はその先頭 12 文字です。
Ollama は digest を指定して pull できないため、tag で pull した後に digest を照合し、一致したときだけ alias を更新します。
tag の内容が上流で更新されると、Renovate が digest を更新するまで (「[依存関係の更新](#依存関係の更新)」) そのモデルは digest 不一致で失敗し、alias は前の版のまま残ります。
alias は Ollama 上で `<alias>:latest` として登録され、Web UI と CLI から参照できます。CLI のモデルはシェルの環境変数で切り替えます (`MODEL=goetia mise run chat`。`.env` の `DEFAULT_MODEL` は既定値、`MODEL` は `.env` では効きません)。
pull や照合に失敗したモデルは警告を出してスキップされ、最後に非 0 で終了します。

## 開発

`mise install` が `prek install` を実行し、`.pre-commit-config.yaml` の hook を commit 時に走らせます。pre-commit では dprint による整形、TOML の構文検査、shellcheck、actionlint と zizmor による workflow の検査、dclint と `docker compose config` による compose ファイルの検査、typos によるスペルチェック、タスク一覧の同期、gitleaks による staged 差分のシークレットスキャンを行い、commit-msg では commitlint が commit message を [Conventional Commits](https://www.conventionalcommits.org/) で検査します。compose ファイルの検証には、compose ファイルの `!reset` タグに対応した Docker Compose が必要です (`compose.apple.yaml` も検査するため)。
手元で全ファイルを検査するには `mise exec -- prek run --all-files` を実行します。
CI (`.github/workflows/ci.yaml`) は pull request で、同じ hook を全ファイルに対して実行する `prek` job と、コミット履歴全体をスキャンする `gitleaks` job を走らせます。
issue や PR のコメントで `@claude` とメンションすると Claude Code が応答し (`claude.yaml`)、毎週月曜には前回以降の差分を Claude Code がレビューして指摘を issue に起票します (`claude-sweep.yaml`)。どちらもリポジトリ secret `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token` で発行) が必要で、`@claude` への応答には [Claude GitHub App](https://github.com/apps/claude) のインストールも必要です。
共通ファイルは [dope-corp/template](https://github.com/dope-corp/template) に揃えており、`mise run template-diff` で差分を確認できます。

### 依存関係の更新

ツール・イメージ・モデルはすべて digest か exact version で固定し、Renovate が毎週月曜 9 時前 (Asia/Tokyo) に更新 PR を作ります。

- `mise.toml` のツールと `mise.lock`、compose ファイル (`compose.yaml`・`compose.apple.yaml`) のイメージ (`<tag>@sha256:<digest>`)、workflow の `uses:` の commit SHA、`.pre-commit-config.yaml` の hook、`dprint.json` の plugin
- `ollama/models.txt` のモデルの digest: Ollama 形式のレジストリは manifest の digest を返さないため、`ollama-models.yaml` が毎日 0 時 (Asia/Tokyo) に各 tag が今指す manifest の sha256 を計算して `ollama-digests` ブランチの `digests.json` に置き、Renovate がそれを読んで更新する。モデルを追加してから最初の計算までは、Renovate の Dependency Dashboard に digest を決められない旨の警告が出る

major 以外の更新は 1 つの PR にまとめ、GitHub の auto-merge で merge します。main の ruleset が CI の `prek` / `gitleaks` の成功を必須にしているので、CI が通るまで merge されません。
Renovate は公開から 7 日経っていない版を待ってから取り込みます (`minimumReleaseAge`)。ただし、公開日時を取得できないもの (ghcr.io のイメージ、tag が付け替えられた action の digest、モデルの digest、`mise.lock` の再生成) は待たずに取り込みます。
major の更新は個別の PR になり、手で確認して merge します。
Ollama は `compose.yaml` のイメージと `mise.toml` (Apple Silicon の構成でホストに入れる版) の 2 か所で固定しており、同じ版に揃えます。片方だけが更新された PR は、もう片方を追従させてから merge します。

## 収録モデル

> **ローカル運用のコンセプト:** Claude Code / Codex では安全フィルターにより拒否されるタスク（セキュリティ研究・exploit 分析・センシティブな創作など）を担うため、拒否を減らしたモデル (重みから拒否の方向を取り除いた abliterated と、追加学習や merge による uncensored) を中心に収録しています。

### 選定基準

用途ごとに、下の表の指標が最も高いモデルを、想定するマシンに載るサイズの中から選んでいます。多くの枠は [UGI Leaderboard](https://huggingface.co/spaces/DontPlanToEnd/UGI-Leaderboard) の指標で選び、コーディング・ペンテスト・長文の枠は表に書いた別の根拠で選びます。UGI Leaderboard は uncensored モデルを、拒否せずに答える度合い (W/10)、センシティブな話題の知識と議論の分かれる指示に従う度合いの総合 (UGI)、一般的な知識・知能 (NatInt) などで比べるベンチマークで、この指標で選ぶ枠では W/10 が 8 未満 (拒否が多い) のモデルを候補から外しています。順位は 2026-10-17 更新のデータ ([ugi-leaderboard-data.csv](https://huggingface.co/spaces/DontPlanToEnd/UGI-Leaderboard/blob/91957a6e66771c651b0c9e472f415cf078091c06/ugi-leaderboard-data.csv)) によるもので、データが更新されると変わりえます。サイズの上限は総パラメータ数 (CSV の `Total Parameters`。MoE も実効パラメータ数ではなく総数) で判定します。

| 用途                                              | 比べる指標                                                                                                                                                                                      | サイズの上限 |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 汎用・セキュリティ                                | UGI (センシティブな話題の知識と、議論の分かれる指示に従う度合いの総合) と Hazardous (LLM が通常は手伝わない話題の知識)                                                                          | 36B          |
| 医療・薬学・法律などの専門知識                    | Textbook (事実・統計・数学・論理の一般知識。専門分野の正確性は測っていない)                                                                                                                     | 36B          |
| 創作・ロールプレイ                                | Writing                                                                                                                                                                                         | 36B          |
| 推論                                              | NatInt (知能の総合)                                                                                                                                                                             | 10B          |
| 軽量・デイリーユース                              | UGI (センシティブな話題の知識と、指示に従う度合いの総合)                                                                                                                                        | 10B          |
| コーディング・エージェント                        | Terminal-Bench 2.1・SWE-bench Pro (各社公式値。UGI Leaderboard は測っていない)                                                                                                                  | 36B          |
| コーディング・エージェント (Apple Silicon の構成) | Ollama の library に MLX 形式の tag しか無いモデルのうち、Terminal-Bench 2.1 (各社公式値) が最も高いもの                                                                                        | 36B          |
| 最も性能の高い abliterated                        | NatInt (知能の総合)。36B 以下と 125B 以下で 1 つずつ                                                                                                                                            | 36B / 125B   |
| 最も性能の高い uncensored                         | NatInt (知能の総合)。36B 以下と 125B 以下で 1 つずつ                                                                                                                                            | 36B / 125B   |
| ペンテスト                                        | 拒否を除去したモデルのうち、ベースの Terminal-Bench 2.1 (端末でツールを使うエージェントの能力) が最も高いもの。同じベースの候補が複数あるときは、配布元の評価で性能の低下が報告されていないもの | 36B / 125B   |
| 1M トークンを超える長文                           | なし (収録モデルで唯一 10M の上限を持つ Llama 4 Scout を置いている)                                                                                                                             | —            |

UGI Leaderboard は 1 つのモデルを thinking の有無で別の行として計測しているので、Ollama で既定のまま使ったときの状態に合う行で比べています。Ollama 0.40.17 は、`think` を指定しない要求でも、thinking に対応した GGUF の chat template では thinking を有効にするので、Qwen3.5 系と Gemma 4 系は thinking 有りの行を使います。thinking の有無で行が分かれていないモデルは、その 1 行を使います。
画像入力は UGI Leaderboard では測っていないので、projector を同梱して画像を受け付けるモデルを用途の欄に挙げています。
abliterated は、拒否に関わる方向を重みから取り除いたモデル (Heretic・Derestricted など) を、uncensored は追加学習や merge で拒否を減らしたモデルを指します。配布元のモデルカードかタグに abliteration (Heretic・Derestricted を含む) で処理したとあれば、`uncensored` のタグが併記されていても abliterated に分類します。1 位が同点のときと、汎用のように 2 つの指標を使う枠で 1 位が分かれたときは UGI が高い方を、UGI も同じなら NatInt が高い方を選びます。125B 以下の枠で 1 位が 36B 以下の枠と同じモデルになるときは、36B を超えるモデルの中の 1 位を選びます。
UGI Leaderboard はコーディングを測っておらず、Qwen3.8 系もまだ計測していないため、コーディングには公式の値で前世代を上回る `qwen38` を置いています。ペンテストは、拒否しないことに加えて、端末でツールを使いながら作業を進める能力が要ります。セキュリティの課題を解く能力を測るベンチマーク (Cybench など) はありますが、今回の候補を横並びで比べた公開結果は無く、候補は UGI Leaderboard にも計測が無いので、一般的な端末作業の能力の代理指標として、ベースモデルの Terminal-Bench 2.1 (配布元の公式値) で比べています。拒否の除去は配布元の評価で確かめています。
長文の枠は W/10 の条件の対象外で、`llama4` は拒否を減らす処理をしていない公式モデル (W/10 5.2) ですが、公称 10M トークンのコンテキストを持つ代わりのモデルが無いので置いています。
モデルを入れ替えるときは、この表の指標で比べ直します。UGI Leaderboard の指標で選ぶ枠には上に書いた条件 (サイズの上限・W/10・thinking の扱い・分類・同点の扱い) を当てはめ、それ以外の枠 (ペンテスト・コーディング・長文) は表に書いた根拠で比べます。Apple Silicon の構成の枠は Ollama の library の MLX 形式の tag から、それ以外の枠は Ollama で pull できる GGUF (単一ファイル) があるものから選びます。

### モデル一覧

| エイリアス                  | ベースモデル                     | アーキテクチャ                      | コンテキスト | サイズ | 主な用途                                                        | 推奨マシン                          |
| --------------------------- | -------------------------------- | ----------------------------------- | ------------ | ------ | --------------------------------------------------------------- | ----------------------------------- |
| `gemma4-31b-heretic:latest` | Google Gemma 4 31B               | Dense 31B                           | 256K         | ~19GB  | 汎用・セキュリティ・CTF・exploit                                | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `qwen35-queen:latest`       | Alibaba Qwen3.5 27B              | Dense 27B                           | 256K         | ~17GB  | 最も性能の高い uncensored (36B 以下)・画像入力                  | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `qwen35-27b-heretic:latest` | Alibaba Qwen3.5 27B              | Dense 27B                           | 256K         | ~17GB  | 医療・薬学・法律などの専門知識・画像入力                        | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `goetia:latest`             | Google Gemma 4 26B-A4B の merge  | MoE (総26B / 実効4B)                | 256K         | ~17GB  | 創作・フィクション・ロールプレイ                                | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `qwen35-9b-heretic:latest`  | Alibaba Qwen3.5 9B               | Dense 9B                            | 256K         | ~6GB   | 推論・脅威分析・ロジック問題・画像入力                          | Apple Silicon 16GB+ / NVIDIA 8GB+   |
| `qwen35-4b-heretic:latest`  | Alibaba Qwen3.5 4B               | Dense 4B                            | 256K         | ~3GB   | 軽量汎用・デイリーユース・画像入力                              | Apple Silicon 8GB+ / NVIDIA 6GB+    |
| `qwen38:latest`             | Alibaba Qwen3.8 27B              | Dense 27B                           | 256K         | ~19GB  | コーディング・エージェント                                      | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `gemma4-26b-heretic:latest` | Google Gemma 4 26B-A4B           | MoE (総26B / 実効4B)                | 256K         | ~18GB  | 最も性能の高い abliterated (36B 以下)・画像入力                 | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `assistant-pepe:latest`     | Meta Llama 3.1 70B               | Dense 70B                           | 128K         | ~43GB  | 最も性能の高い uncensored (36B 超〜125B)                        | Apple Silicon 64GB+ / NVIDIA 48GB+  |
| `xortron-large:latest`      | Mistral Large 2411 123B          | Dense 123B                          | 128K         | ~73GB  | 最も性能の高い abliterated (36B 超〜125B)                       | Apple Silicon 128GB+ / NVIDIA 96GB+ |
| `qwen38-cyber:latest`       | Alibaba Qwen3.8 27B              | Dense 27B                           | 256K         | ~20GB  | ペンテスト (36B 以下)・画像入力                                 | Apple Silicon 32GB+ / NVIDIA 24GB+  |
| `ripple-abliterated:latest` | Ricursive Ripple 65B Preview     | Dense 65B                           | 1M           | ~39GB  | ペンテスト (125B 以下)                                          | Apple Silicon 64GB+ / NVIDIA 48GB+  |
| `inkling2-mini:latest`      | Thinking Machines Inkling 2 Mini | MoE (総26B / 実効5.4B)              | 1M           | ~20GB  | コーディング・エージェント・画像入力 (Apple Silicon の構成だけ) | Apple Silicon 32GB+                 |
| `llama4:latest`             | Meta Llama 4 Scout               | MoE (総109B / 実効17B / 16 experts) | 10M          | ~67GB  | 1M トークンを超える長文、画像入力                               | Apple Silicon 96GB+ / NVIDIA 80GB+  |

サイズは Q4 量子化時のダウンロード容量 (画像入力用の projector を含む) で、起動時に全モデルを pull するのに合計約 360GB (Apple Silicon の構成では `mlx` を付けたモデルの分が加わり約 380GB) のディスクを使います。pull は `ollama/models.txt` の上から順に進み、既定モデルの `qwen35-4b-heretic` を先頭に置いています。実行時はサイズに KV cache 分のメモリが加わります。
推奨マシンは、Apple Silicon はホストの搭載メモリ、NVIDIA は GPU の VRAM の目安です。Ollama をコンテナで動かす構成 (Apple Silicon の構成以外) では、Docker Desktop の VM にもサイズと KV cache が収まるメモリを割り当てる必要があります (Docker Desktop の既定はホストの 50%)。

### モデルの使い分け

```
どれを使えばいいかわからない場合
├── 軽い・速いほうがいい            → qwen35-4b-heretic
├── 何でもこなしたい（汎用）        → gemma4-31b-heretic
├── セキュリティ・CTF・exploit      → gemma4-31b-heretic
├── 医療・薬学・法律の詳細情報     → qwen35-27b-heretic (一般知識の指標で選定。専門分野の正確性は未評価)
├── 小説・RP・NSFW コンテンツ      → goetia
├── 推論が必要な問題（軽量）       → qwen35-9b-heretic
├── コーディング・エージェント     → qwen38 (CLI では `MODEL=qwen38 mise run code`)
├── コーディング (Apple Silicon)   → inkling2-mini (Apple Silicon の構成だけ)
├── 性能重視 (abliterated)          → gemma4-26b-heretic / xortron-large (大型)
├── 性能重視 (uncensored)           → qwen35-queen / assistant-pepe (大型)
├── ペンテスト                     → qwen38-cyber / ripple-abliterated (大型)
├── 画像入力                       → qwen35-queen / qwen35-*-heretic / gemma4-26b-heretic
└── 1M トークンを超える長文       → llama4
```

---

### モデル詳細

エイリアスの `heretic` は、拒否に関わる方向を重みから取り除く (abliteration) ツール Heretic で処理したモデルを指します。Qwen3.5 系と Gemma 4 系は、Ollama で `think` を指定しないと thinking が有効になり、`think: false` で切り替えます。

#### `qwen35-queen:latest`

- **Ollamaタグ:** `hf.co/mradermacher/Qwen3.5-Queen-27B-GGUF:Q4_K_M`
- **特徴:** `Qwen/Qwen3.5-27B` を aifeifei798 が追加学習したもの。abliteration ではなく学習で拒否を減らしており、配布元はロールプレイと複数の persona を演じることを特徴に挙げている。36B 以下の uncensored で NatInt が最も高い。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `qwen35-27b-heretic:latest`

- **Ollamaタグ:** `hf.co/llmfan46/Qwen3.5-27B-uncensored-heretic-v1-GGUF:Q4_K_M`
- **特徴:** Qwen3.5 27B を Heretic で abliteration したもの (UGI Leaderboard 上の名前は `llmfan46/Qwen3.5-27B-heretic-v3`)。36B 以下で Textbook が最も高い。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `goetia:latest`

- **Ollamaタグ:** `hf.co/mradermacher/Goetia-26B-A4B-v1.3-Absolute-Heretic-ARA-GGUF:Q4_K_M`
- **特徴:** Gemma 4 26B-A4B 系の創作向けモデル (StyleTune・Pantheon など) を Naphula が mergekit で合成し、Heretic で abliteration したもの。36B 以下で Writing が最も高い (47.87)。この GGUF には projector が無く、画像入力には対応しない。
- **ライセンス:** Apache 2.0

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

#### `gemma4-31b-heretic:latest`

- **Ollamaタグ:** `hf.co/mradermacher/gemma-4-31B-it-heretic-GGUF:Q4_K_M`
- **特徴:** `google/gemma-4-31B-it` を coder3101 が Heretic で abliteration したもの。36B 以下で UGI が最も高い (65.69)。Hazardous は同じ Gemma 4 31B を llmfan46 が処理した版の 8.2 が 1 位で、こちらは 7.6。この GGUF には projector が無く、画像入力には対応しない。
- **ライセンス:** Apache 2.0

#### `gemma4-26b-heretic:latest`

- **Ollamaタグ:** `hf.co/llmfan46/gemma-4-26B-A4B-it-uncensored-heretic-GGUF:Q4_K_M`
- **特徴:** `google/gemma-4-26B-A4B-it` を llmfan46 が Heretic で abliteration したもの。36B 以下の abliterated で NatInt が最も高い (37.3)。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `assistant-pepe:latest`

- **Ollamaタグ:** `hf.co/SicariusSicariiStuff/Assistant_Pepe_70B_GGUF:Q4_K_M`
- **特徴:** `meta-llama/Llama-3.1-70B-Instruct` を SicariusSicariiStuff が 4chan のデータで追加学習したもの。125B 以下の uncensored で NatInt が最も高い。システムプロンプトが無くても使えるように学習されている。画像入力には対応しない。
- **ライセンス:** Llama 3.1 Community License

#### `xortron-large:latest`

- **Ollamaタグ:** `hf.co/mradermacher/XORTRON.CriminalComputing.LARGE.2026.3-GGUF:Q4_K_M`
- **特徴:** `mistralai/Mistral-Large-Instruct-2411` を darkc0de が Heretic で abliteration したもの。36B を超え 125B 以下のモデルで NatInt と UGI がともに最も高い (UGI は収録モデルの中でも最も高い 66.16)。Dense 123B なので、同じメモリに載る MoE より生成は遅い。画像入力には対応しない。
- **ライセンス:** 配布元は WTFPL と表記 (派生元の Mistral Large 2411 は Mistral Research License)

#### `qwen38-cyber:latest`

- **Ollamaタグ:** `hf.co/philbert440/Qwen3.8-27B-Uncensored-Cyber-GGUF:Q4_K_M`
- **特徴:** `Qwen/Qwen3.8-27B` を philbert440 が、攻撃的なセキュリティの質問に答えるよう abliteration したもの。配布元の評価では、攻撃的なサイバー系のプロンプト 100 件にすべて回答している。ベースの Qwen3.8-27B は Terminal-Bench 2.1 73.0 で、36B 以下で最も高い。thinking は GGUF の chat template の既定で有効。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `ripple-abliterated:latest`

- **Ollamaタグ:** `hf.co/0xKitkat/Ripple-65B-Preview-abliterated-GGUF:Q4_K_M`
- **特徴:** `ricursiveAI/Ripple-65B-Preview` (agentic coding 向けの Dense 65B) を 0xKitkat が abliteration したもの。ベースの Terminal-Bench 2.1 は 80.5 で、収録モデルのベースのうち公式値があるものの中で最も高い。配布元の評価では、有害なプロンプト 48 件のうち拒否は 1 件で、配布元が試した小規模な機能テスト (推論・コード・ツール呼び出し) では元のモデルとほぼ差が無い (エージェントとしての評価は未実施)。同じ Ripple を abliteration した dealignai 版は、MMLU が 4.4 ポイント下がると計測されているので、低下を示す計測の無いこちらを選んだ。応答の前に `<think>` で推論を書くモデルで、chat template に thinking の切り替えは無い。公称のコンテキスト長は 1M トークン (GGUF のメタデータの値は 2M。Ollama での指定は `llama4` の備考と同じ)。画像入力には対応しない。
- **ライセンス:** Apache 2.0
- **備考:** 独自の `ricursive` アーキテクチャで、Ollama 0.40.16 以降が必要。

#### `inkling2-mini:latest`

- **Ollamaタグ:** `inkling-2-mini:26b-a5b-nvfp4` (MLX 形式)
- **特徴:** Thinking Machines の公式モデル。拒否を減らす処理はしていない。Ollama の library の tag は MLX 形式だけなので、このリポジトリでは「[Apple Silicon の構成](#apple-silicon-の構成)」でだけ pull する (Hugging Face には GGUF もあるが、Ollama 0.40.17 はこの構成以外での実行に対応していない)。公式の比較では Terminal-Bench 2.1 が 71.6 (`qwen38` のベースの Qwen3.8-27B は 73.0)、DeepSWE 1.1 が 48.2 (同 42.2) で、実効パラメータは 5.4B の MoE。thinking は既定で有効で、Ollama の `think` で切り替える。画像入力に対応。
- **ライセンス:** Apache 2.0

#### `llama4:latest`

- **Ollamaタグ:** `llama4:17b-scout-16e-instruct-q4_K_M`
- **特徴:** Meta 公式の Llama 4 Scout。拒否を減らす処理はしていない。収録モデルで最も長いコンテキスト (公称 10M トークン) を持つ。画像入力にも対応。総パラメータ 109B のため Q4 でも 67GB を要する。
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

## `serve`

- **Usage:** `serve`

Apple Silicon の構成で、ホストの Ollama を起動する (`mise run up` の前に別のターミナルで実行し、Ctrl-C で止める)

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
