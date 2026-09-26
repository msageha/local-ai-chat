# local-ai-chat

ローカルで動作する AI チャット環境。ChatGPT 風 Web UI と Claude Code / Codex 風 CLI を Docker Compose で一括起動します。

## サービス構成

| サービス      | 説明                                                                | デフォルトポート |
| ------------- | ------------------------------------------------------------------- | ---------------- |
| `ollama`      | LLM バックエンド (OpenAI 互換 API)                                  | 11434            |
| `ollama-init` | 起動時に `ollama/models.txt` のモデルを pull してエイリアスを付ける | — (完了後に終了) |
| `open-webui`  | ChatGPT 風 Web UI                                                   | 3000             |
| `cli`         | aider ベースの Claude Code / Codex 風 CLI                           | — (対話型)       |

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

`ollama/models.txt` に 1 行 `<alias> <source>` で追記し、`mise run pull` を実行します。
alias は Ollama 上で `<alias>:latest` として登録され、Web UI と CLI から参照できます。CLI のモデルはシェルの環境変数で切り替えます (`MODEL=dolphin mise run chat`。`.env` の `DEFAULT_MODEL` は既定値、`MODEL` は `.env` では効きません)。
pull に失敗したモデルは警告を出してスキップされ、最後に非 0 で終了します。

## 開発

`mise install` が `prek install` を実行し、`.pre-commit-config.yaml` の hook (dprint による整形、shellcheck、actionlint、compose ファイルの検証、タスク一覧の同期) を commit 時に走らせます。compose ファイルの検証には Docker CLI が必要です。
手元で全ファイルを検査するには `prek run --all-files` を実行します。
CI (`.github/workflows/ci.yaml`) は同じ hook を全ファイルに対して実行し、gitleaks でシークレットをスキャンします。
ツールのバージョンは `mise.toml`、イメージのバージョンは `compose.yaml` に固定し、更新は Renovate と `mise-lock.yaml` に任せます。

## 収録モデル

> **ローカル運用のコンセプト:** Claude Code / Codex では安全フィルターにより拒否されるタスク（セキュリティ研究・exploit 分析・センシティブな創作など）を担うため、uncensored / abliterated モデルを中心に収録しています。

### モデル一覧

| エイリアス             | ベースモデル                            | アーキテクチャ                      | コンテキスト | サイズ | 主な用途                                                 | 推奨マシン                         |
| ---------------------- | --------------------------------------- | ----------------------------------- | ------------ | ------ | -------------------------------------------------------- | ---------------------------------- |
| `super-gemma:latest`   | Google Gemma 4 26B-A4B                  | MoE (総26B / 実効4B)                | 256K         | ~17GB  | 汎用・コーディング・reasoning                            | Apple Silicon 32GB+ / NVIDIA 24GB+ |
| `llama4:latest`        | Meta Llama 4 Scout                      | MoE (総109B / 実効17B / 16 experts) | 10M          | ~67GB  | 汎用・マルチモーダル・ツール呼び出し                     | Apple Silicon 96GB+ / NVIDIA 80GB+ |
| `qwen35:latest`        | Alibaba Qwen3.5 9B                      | Dense 9B (abliterated)              | 256K         | ~7GB   | 軽量汎用・デイリーユース・画像入力                       | Apple Silicon 16GB+ / NVIDIA 12GB+ |
| `dark-champion:latest` | Llama 3.2 4B × 8 MoE (Dark Champion V2) | MoE (総21B / 8 experts)             | 128K         | ~13GB  | クリエイティブ執筆・フィクション・ロールプレイ           | Apple Silicon 32GB+ / NVIDIA 16GB+ |
| `dolphin:latest`       | Dolphin Mistral 24B Venice Edition      | Dense 24B (uncensored)              | 32K          | ~14GB  | セキュリティ研究・CTF・ペネトレーション・汎用 uncensored | Apple Silicon 32GB+ / NVIDIA 16GB+ |
| `deepseek-r1:latest`   | DeepSeek R1-0528 Qwen3 8B 蒸留          | Dense 8B (abliterated)              | 128K         | ~5GB   | 推論チェーン × uncensored（脅威分析・ロジック問題）      | Apple Silicon 16GB+ / NVIDIA 8GB+  |
| `hermes:latest`        | Nous Hermes 4.3 36B                     | Dense 36B (低拒否率設計)            | 512K         | ~22GB  | 医療・薬学・法律グレーゾーン・専門知識                   | Apple Silicon 48GB+ / NVIDIA 24GB+ |
| `qwen38:latest`        | Alibaba Qwen3.8 27B                     | Dense 27B (uncensored / aggressive) | 256K         | ~18GB  | 高品質汎用・長文・コーディング (アグレッシブ uncensored) | Apple Silicon 32GB+ / NVIDIA 24GB+ |

サイズは Q4 量子化時のダウンロード容量です。実行時はこれに KV cache 分のメモリが加わります。

### モデルの使い分け

```
どれを使えばいいかわからない場合
├── 軽い・速いほうがいい          → qwen35 / deepseek-r1
├── 何でもこなしたい（汎用）      → super-gemma / qwen38
├── 小説・RP・NSFW コンテンツ    → dark-champion
├── セキュリティ・CTF・exploit    → dolphin
├── 推論が必要な難問・脅威分析   → deepseek-r1
├── 医療・薬学・法律の詳細情報   → hermes
└── 巨大コンテキスト・画像入力   → llama4
```

---

### モデル詳細

#### `super-gemma:latest`

- **Ollamaタグ:** `0xIbra/supergemma4-26b-uncensored-gguf-v2:Q4_K_M`
- **特徴:** `google/gemma-4-26B-A4B-it` ベースのアンセンサード版。thinking mode 対応（システムプロンプトに `<|think|>` を付与）。英語・韓国語対応。
- **推奨マシン:** Apple Silicon 32GB 以上 / NVIDIA 24GB 以上
- **ライセンス:** Gemma Terms of Use

#### `llama4:latest`

- **Ollamaタグ:** `llama4:17b-scout-16e-instruct-q4_K_M`
- **特徴:** Meta 公式の Llama 4 Scout。マルチモーダル対応（テキスト＋画像入力）。10M トークンのコンテキスト長。多言語対応。総パラメータ 109B のため Q4 でも 67GB を要する。
- **推奨マシン:** Apple Silicon 96GB 以上 / NVIDIA 80GB 以上
- **ライセンス:** Llama 4 Community License

#### `qwen35:latest`

- **Ollamaタグ:** `huihui_ai/qwen3.5-abliterated:9b-q4_K`
- **特徴:** Qwen3.5 9B の abliterated 版（安全フィルター除去）。ネイティブマルチモーダルで画像入力に対応。最も軽量でデイリーユースに最適。デフォルトモデル。
- **推奨マシン:** Apple Silicon 16GB 以上 / NVIDIA 12GB 以上
- **ライセンス:** Apache 2.0

#### `dark-champion:latest`

- **Ollamaタグ:** `hf.co/DavidAU/Llama-3.2-8X4B-MOE-V2-Dark-Champion-Instruct-uncensored-abliterated-21B-GGUF:Q4_K_M`
- **特徴:** DavidAU による Dark Champion の V2。Llama 3.2 系 4B モデル 8 本を MoE 合成した 21B モデル（V1 は 3B × 8 の 18.4B）。クリエイティブ執筆・フィクション・ロールプレイに特化。NSFW 出力あり。
- **推奨マシン:** Apple Silicon 32GB 以上 / NVIDIA 16GB 以上（MoE は GPU 並列処理との相性が良い）
- **ライセンス:** Apache 2.0（リポジトリ表記。派生元は Llama 3.2 Community License）

#### `dolphin:latest`

- **Ollamaタグ:** `hf.co/bartowski/cognitivecomputations_Dolphin-Mistral-24B-Venice-Edition-GGUF:Q4_K_M`
- **特徴:** Eric Hartford (cognitivecomputations) が Venice.ai と共同で公開した Dolphin シリーズの最新版。Mistral Small 24B ベースで、Dolphin 3 8B より大幅に高性能。安全フィルターを除去した汎用モデルで、Claude Code / Codex が拒否するセキュリティ関連タスク（CTF、ペネトレーションテスト、exploit の仕組み解説、PoC コード生成）に特に有用。コンテキストは GGUF の設定値どおり 32K（Dolphin 3 8B の 128K より短い）。
- **推奨マシン:** Apple Silicon 32GB 以上 / NVIDIA 16GB 以上
- **Claude Code との差分:** exploit コード生成・マルウェア解析・ソーシャルエンジニアリング手法の説明など Claude が拒否するタスクを実行可能
- **ライセンス:** Apache 2.0

#### `deepseek-r1:latest`

- **Ollamaタグ:** `huihui_ai/deepseek-r1-abliterated:8b-0528-qwen3-q4_K_M`
- **特徴:** DeepSeek R1-0528 を Qwen3 8B に蒸留した公式モデル（DeepSeek-R1-0528-Qwen3-8B）の abliterated 版。初代 R1 蒸留 14B より新しい世代で、`<think>` タグで推論チェーンを可視化しながら回答する。安全フィルター除去により、脅威モデリング・セキュリティアーキテクチャの分析・危険なロジックを含む問題の段階的解決が可能。
- **推奨マシン:** Apple Silicon 16GB 以上 / NVIDIA 8GB 以上
- **Claude Code との差分:** セキュリティ上センシティブな仮説に基づく推論・「なぜ攻撃が成立するか」の詳細論理展開など
- **ライセンス:** MIT

#### `hermes:latest`

- **Ollamaタグ:** `hf.co/NousResearch/Hermes-4.3-36B-GGUF:Q4_K_M`
- **特徴:** Nous Research 公式の最新世代 Hermes 4.3（ByteDance Seed-OSS 36B ベース、2025-12 公開）。Hermes 4 以降は「中立的な alignment」を掲げ、システムプロンプトに従って免責事項や拒否を挟まずに回答するよう学習されているため abliteration 版を使わない。医療・薬学・法律など、通常の AI が曖昧にする専門領域で直接的な回答を提供する。
- **推奨マシン:** Apple Silicon 48GB 以上 / NVIDIA 24GB 以上
- **Claude Code との差分:** 「医師に相談してください」「法律の専門家に確認してください」といった回避をせず、具体的な情報を直接提供
- **ライセンス:** Apache 2.0
- **備考:** メモリが足りない場合は Hermes 4 14B の abliterated 版 `hf.co/mradermacher/Hermes-4-14B-BF16-abliterated-GGUF:Q4_K_M`（約 9GB、コンテキスト 40K）が軽量な代替になる

#### `qwen38:latest`

- **Ollamaタグ:** `hf.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF:Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf`
- **特徴:** Qwen3.8 27B をベースに HauhauCS が Uncensored 化した "Aggressive" 版（拒否率を最小化し直接的に回答）の最新世代。imatrix を用いた独自 K_P 量子化（Q4_K_P, 18GB）で同サイズ標準量子化より品質劣化が小さい。GGUF に multi-token prediction (MTP) 用のヘッドを同梱。画像入力用の projector (mmproj) も一緒に pull されるが、画像入力の動作は未検証。
- **推奨マシン:** Apple Silicon 32GB 以上 / NVIDIA 24GB 以上
- **Claude Code との差分:** 27B クラスの汎用品質を保ったままセキュリティ・創作・センシティブ領域で拒否を返さない
- **ライセンス:** Apache 2.0
- **備考:** K_P 量子化は Hugging Face の Ollama 互換エンドポイントが量子化名として認識しないため、tag には量子化名ではなく GGUF のファイル名を指定している。MTP ヘッドも非標準のため Ollama バージョンによっては読み込みに失敗することがあり、その場合は同世代の素の abliterated 版 `huihui_ai/Qwen3.8-abliterated:27b`（18GB）への差し替えを検討

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

## `ui`

- **Usage:** `ui`

Web UI をブラウザで開く

## `up`

- **Usage:** `up`

全サービスを起動する。モデルの pull はバックグラウンドで進む (`mise run logs` で確認)
<!-- /mise-tasks -->
<!-- dprint-ignore-end -->
