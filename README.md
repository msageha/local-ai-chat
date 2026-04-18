# local-ai-chat

ローカルで動作する AI チャット環境。ChatGPT 風 Web UI と Claude Code / Codex 風 CLI を Docker Compose で一括起動します。

## サービス構成

| サービス | 説明 | デフォルトポート |
|---------|------|----------------|
| `ollama` | LLM バックエンド (OpenAI 互換 API) | 11434 |
| `open-webui` | ChatGPT 風 Web UI | 3000 |
| `cli` | Claude Code / Codex 風 CLI | — (対話型) |

## 収録モデル

> **ローカル運用のコンセプト:** Claude Code / Codex では安全フィルターにより拒否されるタスク（セキュリティ研究・exploit 分析・センシティブな創作など）を担うため、uncensored / abliterated モデルを中心に収録しています。

### モデル一覧

| エイリアス | ベースモデル | アーキテクチャ | コンテキスト | サイズ | 主な用途 | 推奨マシン |
|-----------|-------------|--------------|------------|--------|---------|-----------|
| `super-gemma:latest` | Google Gemma 4 26B | MoE (総26B / 実効4B) | 256K | ~17GB | 汎用・コーディング・reasoning | Apple Silicon 32GB+ |
| `llama4:latest` | Meta Llama 4 Scout | MoE (総109B / 実効17B / 16 experts) | 10M | ~12GB | 汎用・マルチモーダル・ツール呼び出し | Apple Silicon / NVIDIA 16GB+ |
| `qwen25:latest` | Alibaba Qwen 2.5 7B | Dense 7B (abliterated) | ~4K | ~5GB | 軽量汎用・デイリーユース | Apple Silicon 16GB+ / NVIDIA 8GB+ |
| `dark-champion:latest` | Llama 3.2 3B × 8 MoE | MoE (総18.4B / 8 experts) | 128K | ~11GB | クリエイティブ執筆・フィクション・ロールプレイ | NVIDIA 16GB+ |
| `dolphin:latest` | Llama 3.1 8B | Dense 8B (uncensored) | 128K | ~5GB | セキュリティ研究・CTF・ペネトレーション・汎用 uncensored | Apple Silicon 16GB+ / NVIDIA 8GB+ |
| `deepseek-r1:latest` | DeepSeek R1 Distill 14B | Dense 14B (abliterated) | 128K | ~9GB | 推論チェーン × uncensored（脅威分析・ロジック問題） | Apple Silicon 32GB+ / NVIDIA 16GB+ |
| `hermes:latest` | Nous Hermes 3 8B | Dense 8B (abliterated) | 128K | ~5GB | 医療・薬学・法律グレーゾーン・専門知識 | Apple Silicon 16GB+ / NVIDIA 8GB+ |

### モデルの使い分け

```
どれを使えばいいかわからない場合
├── 軽い・速いほうがいい          → qwen25
├── 何でもこなしたい（汎用）      → super-gemma / llama4
├── 小説・RP・NSFW コンテンツ    → dark-champion
├── セキュリティ・CTF・exploit    → dolphin
├── 推論が必要な難問・脅威分析   → deepseek-r1
└── 医療・薬学・法律の詳細情報   → hermes
```

---

### モデル詳細

#### `super-gemma:latest`
- **Ollamaタグ:** `0xIbra/supergemma4-26b-uncensored-gguf-v2:Q4_K_M`
- **特徴:** Apple Silicon 向けに最適化された MLX ラインからの GGUF 変換。アンセンサード。thinking mode 対応（システムプロンプトに `<|think|>` を付与）。英語・韓国語対応。
- **推奨マシン:** Apple Silicon 32GB 以上（VRAM 消費が大きいため）
- **ライセンス:** Gemma 派生（非明示）

#### `llama4:latest`
- **Ollamaタグ:** `llama4:17b-scout-16e-instruct-q4_K_M`
- **特徴:** Meta 公式の最新 Llama 4 Scout。唯一のマルチモーダル対応モデル（テキスト＋画像入力）。10M トークンという破格のコンテキスト長。多言語対応。リリース日: 2025-04-05。
- **推奨マシン:** Apple Silicon 16GB+ または NVIDIA 16GB+
- **ライセンス:** Llama 4 Community License

#### `qwen25:latest`
- **Ollamaタグ:** `aispin/qwen2.5-7b-instruct-abliterated-v2.q4_k_s.gguf`
- **特徴:** Qwen 2.5 7B の abliterated 版（安全フィルター除去）。最も軽量でデイリーユースに最適。Mac / NVIDIA どちらでも問題なく動作。デフォルトモデル。
- **推奨マシン:** Apple Silicon 16GB+ / NVIDIA 8GB+（最も要件が低い）
- **ライセンス:** Apache 2.0

#### `dark-champion:latest`
- **Ollamaタグ:** `dfebrero/DavidAU-Llama-3.2-8X3B-MOE-Dark-Champion-Instruct-uncensored-abliterated-18.4B`
- **特徴:** Llama 3.2 3B モデル 8 本を MoE 合成した 18.4B モデル。クリエイティブ執筆・フィクション・ロールプレイに特化。NSFW 出力あり。16GB VRAM カードで 50+ tokens/sec。
- **推奨マシン:** NVIDIA 16GB+（MoE は GPU 並列処理との相性が良い）
- **ライセンス:** Llama 3 Community License

#### `dolphin:latest`
- **Ollamaタグ:** `dolphin3:8b`
- **特徴:** Eric Hartford が開発する定番 uncensored シリーズ Dolphin の最新版。安全フィルターを完全に除去した汎用モデル。Claude Code / Codex が拒否するセキュリティ関連タスク（CTF、ペネトレーションテスト、exploit の仕組み解説、PoC コード生成）に特に有用。コンテキスト 128K で長いコードや会話もこなせる。
- **推奨マシン:** Apple Silicon 16GB+ / NVIDIA 8GB+
- **Claude Code との差分:** exploit コード生成・マルウェア解析・ソーシャルエンジニアリング手法の説明など Claude が拒否するタスクを実行可能
- **ライセンス:** Apache 2.0

#### `deepseek-r1:latest`
- **Ollamaタグ:** `huihui-ai/deepseek-r1-abliterated:14b`
- **特徴:** DeepSeek R1 Distill 14B の abliterated 版。`<think>` タグで推論チェーン（Chain of Thought）を可視化しながら回答する。安全フィルター除去により、脅威モデリング・セキュリティアーキテクチャの分析・危険なロジックを含む問題の段階的解決が可能。純粋な推論力は同サイズ最高水準。
- **推奨マシン:** Apple Silicon 32GB+ / NVIDIA 16GB+（14B のため要求スペックが高め）
- **Claude Code との差分:** セキュリティ上センシティブな仮説に基づく推論・「なぜ攻撃が成立するか」の詳細論理展開など
- **ライセンス:** MIT (DeepSeek R1 Distill)

#### `hermes:latest`
- **Ollamaタグ:** `huihui-ai/hermes3-abliterated:8b`
- **特徴:** Nous Research の Hermes 3 8B の abliterated 版。医療・薬学・法律など、通常の AI が免責事項で曖昧にする専門領域で直接的な回答を提供する。薬物相互作用の詳細・手術手技の解説・法律グレーゾーンの分析など。instruction following 能力が高く、プロンプト通りに動く。
- **推奨マシン:** Apple Silicon 16GB+ / NVIDIA 8GB+
- **Claude Code との差分:** 「医師に相談してください」「法律の専門家に確認してください」といった回避をせず、具体的な情報を直接提供
- **ライセンス:** Apache 2.0
