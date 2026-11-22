# 開発

## commit 時の検査

`mise install` が [prek](https://github.com/j178/prek) で git の hook を設定し、commit のたびに `.pre-commit-config.yaml` の検査を走らせます。

| 対象                       | 検査                                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| すべてのファイル           | 行末の空白・末尾の改行・改行コードの混在・conflict marker・新しく追加する大きなファイル                 |
| JSON・YAML・TOML・Markdown | 構文 (JSON・YAML・TOML。`compose.apple.yaml` は compose ファイルの検査で確かめる) と、dprint による整形 |
| シェルスクリプト           | shellcheck                                                                                              |
| GitHub Actions の workflow | actionlint・zizmor                                                                                      |
| compose ファイル           | dclint と `docker compose config` (GPU と Apple Silicon の構成もそれぞれ重ねて検査する)                 |
| Ollama の版                | `compose.yaml` のイメージと `mise.toml` のホスト用の版が一致するか                                      |
| 綴り                       | typos                                                                                                   |
| README のタスク一覧        | `mise.toml` を変えたときに `mise run docs` で再生成する                                                 |
| staged の差分              | gitleaks による secret の検出                                                                           |
| commit message             | commitlint による [Conventional Commits](https://www.conventionalcommits.org/) の検査                   |

compose ファイルの検査には、`compose.apple.yaml` の `!reset` タグに対応した Docker Compose が要ります。

全ファイルを検査するには `mise exec -- prek run --all-files` を実行します。commit message の検査は含まれません。整形とタスク一覧の再生成は、ファイルを書き換えることがあります。

## CI と GitHub Actions

| workflow             | 動く契機                 | 内容                                                                                                                          |
| -------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `ci.yaml`            | pull request             | `prek` job が全ファイルに上の検査 (commit message の検査を除く) をかけ、`gitleaks` job が commit の履歴全体から secret を探す |
| `claude.yaml`        | issue・PR での `@claude` | OWNER か MEMBER のメンションに Claude Code が応答する                                                                         |
| `claude-sweep.yaml`  | 毎週月曜                 | 前回成功した回以降の差分を Claude Code がレビューし、指摘を issue に起票する。初回と、差分が無い回はレビューしない            |
| `ollama-models.yaml` | 毎日 0 時 (Asia/Tokyo)   | モデルの digest を計算する (「[依存関係の更新](#依存関係の更新)」)                                                            |

Claude Code の workflow には、リポジトリの secret `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token` で発行) が要ります。`@claude` への応答には、[Claude GitHub App](https://github.com/apps/claude) のインストールも要ります。

## 共通ファイル

設定ファイルなどの共通ファイルは [dope-corp/template](https://github.com/dope-corp/template) にそろえています。`mise run template-diff` で template との差分を確認できます。

## 依存関係の更新

ツール・イメージ・モデルは、すべて digest か exact version で固定しています。Renovate は、毎週月曜 9 時前 (Asia/Tokyo) の時間帯に、次のものに更新があれば PR を作ります。

- `mise.toml` のツールと `mise.lock`
- compose ファイル (`compose.yaml`・`compose.apple.yaml`) のイメージ (`<tag>@sha256:<digest>`)
- workflow の `uses:` の commit SHA
- `.pre-commit-config.yaml` の hook と `dprint.json` の plugin
- `ollama/models.txt` のモデルの digest

### merge の扱い

- major 以外の更新 (minor・patch・pin・digest・pinDigest) は 1 つの PR にまとめ、GitHub の auto-merge で merge します。
- `mise.lock` の再生成 (lock file maintenance) は別の PR になり、同じく auto-merge で merge します。
- major の更新は個別の PR になり、手で確認して merge します。
- auto-merge は、main の ruleset が必須にしている CI の `prek` と `gitleaks` が通るまで待ちます。

Renovate は、公開から 7 日経っていない版を待ってから取り込みます (`minimumReleaseAge`)。ただし、公開日時を取得できないもの (ghcr.io のイメージ、tag が付け替えられた action の digest、モデルの digest、`mise.lock` の再生成) は待たずに取り込みます。

### モデルの digest

Ollama 形式のレジストリは manifest の digest を返さないので、Renovate はモデルの digest を自分で求められません。代わりに `ollama-models.yaml` が毎日 0 時 (Asia/Tokyo) に、`ollama/models.txt` の各 tag が今指す manifest の sha256 を計算し、`ollama-digests` ブランチの `digests.json` に置きます。Renovate はこれを読んで digest を更新します。モデルを追加してから最初の計算までは、Renovate の Dependency Dashboard に digest を決められないという警告が出ます。

### Ollama の版

Ollama は、`compose.yaml` のイメージと、`mise.toml` (Apple Silicon の構成でホストに入れる版) の 2 か所で固定しており、同じ版にそろえます。片方だけを更新する PR は、もう片方を追従させてから merge します。
