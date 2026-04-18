# local-ai-chat

ローカルで動作する AI チャット環境。ChatGPT 風 Web UI と Claude Code / Codex 風 CLI を Docker Compose で一括起動します。

## サービス構成

| サービス | 説明 | デフォルトポート |
|---------|------|----------------|
| `ollama` | LLM バックエンド (OpenAI 互換 API) | 11434 |
| `open-webui` | ChatGPT 風 Web UI | 3000 |
| `cli` | Claude Code / Codex 風 CLI | — (対話型) |

## 収録モデル

| エイリアス | モデル名 |
|-----------|---------|
| `super-gemma` | Super Gemma 4 26B Uncensored (`super-gemma:latest`) |
| `llama4` | Llama 4 Scout 17B-16E Abliterated (`llama4:latest`) |
| `qwen25` | Qwen 2.5 7B Abliterated (`qwen25:latest`) |
| `dark-champion` | LLaMA-3.2 Dark Champion 18.4B Abliterated (`dark-champion:latest`) |

> **Note**: Meta の Llama 4 は MoE アーキテクチャを採用しており、70B dense モデルは存在しません。  
> `llama4` エイリアスは最も近い公開モデル「Llama 4 Scout 17B-16E Abliterated」を指します。

## クイックスタート

```bash
# 1. 設定ファイルをコピー
cp .env.example .env

# 2. バックエンド + UI を起動 (初回はモデルの自動ダウンロードが走ります)
make up          # または: docker compose up -d ollama open-webui

# 3. ブラウザで Web UI を開く
make ui          # http://localhost:3000

# 4. CLI を使う
make chat                    # チャットモード
make chat MODEL=dark-champion

make code                    # コードアシスタントモード (カレントディレクトリをマウント)
make code MODEL=llama4

make models                  # 使用可能なモデル一覧
make pull MODEL=llama4       # alias 付きでモデルを手動 pull
```

## CLI 使い方

```
aicli chat [--model ALIAS]   # Interactive chat
aicli code [--model ALIAS]   # Code assistant (filesystem access)
aicli models                 # List models
aicli pull  <alias>          # Pull a model
```

### code モードのスラッシュコマンド

| コマンド | 説明 |
|---------|------|
| `/read <file>` | ファイルを読み込んでコンテキストに追加 |
| `/tree [dir]` | ディレクトリツリーを表示 |
| `/run <cmd>` | シェルコマンドを実行 (確認あり) |
| `/model <alias>` | モデルを切り替え |
| `/clear` | 会話履歴をクリア |
| `/quit` | 終了 |

## GPU を使わない場合

`docker-compose.yml` の `ollama` サービスから `deploy` ブロックを削除してください:

```yaml
# 以下を削除:
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

## モデルの自動ダウンロードをスキップ

`.env` で `PULL_MODELS=false` に設定すると、起動時のモデル pull をスキップできます。  
その場合は `make pull MODEL=<alias>` で個別に pull してください。

## ログ確認

```bash
make logs                          # 全サービス
docker compose logs -f ollama      # Ollama のみ
docker compose logs -f open-webui  # UI のみ
```
# local-ai-chat
