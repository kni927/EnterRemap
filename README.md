# EnterRemap

macOS用のIMEセーフな Enter/Cmd+Enter リマップ常駐ツール。
対象のAIチャット系ネイティブアプリで、Enterの誤送信を防ぐ。

- **Enter** → 改行(Shift+Enterに変換)
- **Cmd+Enter** → 送信(Cmdを外してEnterに変換)
- **Shift+Enter** → そのまま(改行)
- **IME変換中のEnter** → そのまま(変換確定に使わせる)

## 対象アプリ

bundle ID許可リスト方式(前面アプリのbundle IDで判定)。

| アプリ | Bundle ID |
|---|---|
| Claude | `com.anthropic.claudefordesktop` |
| ChatGPT(新統合版) | `com.openai.codex` |
| ChatGPT Classic | `com.openai.chat` |
| Gemini | `com.google.GeminiMacOS` |

アプリの追加は [main.swift](main.swift) の `ALLOWED_BUNDLE_IDS` に1行追加するだけ。

Web版(ブラウザ)は対象外 — Chrome拡張(Chat AI Ctrl+Enter Sender等)で対応済み。

## IME判定の仕組み(v1.1)

Enter押下時のみ、多層チェックで「今まさに変換中か」を判定する
(詳細: [docs/2026-07-12-ime-detection-notes.md](docs/2026-07-12-ime-detection-notes.md))。

1. `eventSourceStateID != 1` → IME由来イベント(Apple標準日本語入力の確定Enter)
2. 現在の入力ソースが英数/非IME → 非変換中(TIS照会 ~0.01ms)
3. フォーカス要素の `AXHasMarkedText`(取得できる場合のみ)
4. IMEプロセス所有のオンスクリーンウィンドウ検出(~1.7ms) —
   Google日本語入力のサジェスト/候補ウィンドウを検出する

最悪経路でも合計 ~2ms で、体感遅延はない。

診断モード: `/Applications/EnterRemap.app/Contents/MacOS/EnterRemap --probe`
を実行すると、各シグナルの値とレイテンシを1秒間隔で10回ダンプする
(変換中の状態を確認したいときに使う)。

## ビルド & インストール

```bash
./build.sh
```

`build/EnterRemap.app` を生成し、`/Applications/EnterRemap.app` へインストールする。

初回セットアップ:

1. **システム設定 > プライバシーとセキュリティ > アクセシビリティ** に EnterRemap を追加して許可
2. **システム設定 > 一般 > ログイン項目** に EnterRemap を追加(常駐化)
3. 起動: `open /Applications/EnterRemap.app`

注意: ad-hoc署名のため、再ビルド後はアクセシビリティ許可の再付与
(一度削除して再追加)が必要になる場合がある。

## Workflow

This project follows a Chat-then-Code workflow:

1. Architecture/design decisions are made in chat and written into `TASK.md`.
2. Claude Code implements against `TASK.md`, committing per task.
3. Completed task phases are archived under `docs/tasks/`.

See `CLAUDE.md` for details.
