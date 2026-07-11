# EnterRemap

macOS用のIMEセーフな Enter/Cmd+Enter リマップ常駐ツール。
対象のAIチャット系ネイティブアプリで、Enterの誤送信を防ぐ。

- **Enter** → 改行(Shift+Enterに変換)
- **Cmd+Enter** → 送信(Cmdを外してEnterに変換)
- **Shift+Enter** → そのまま(改行)
- **IME確定のEnter** → そのまま(`eventSourceStateID`判定により変換しない)

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

## ビルド & インストール

```bash
./build.sh
```

`build/EnterRemap.app` を生成し、`~/Applications/EnterRemap.app` へインストールする。

初回セットアップ:

1. **システム設定 > プライバシーとセキュリティ > アクセシビリティ** に EnterRemap を追加して許可
2. **システム設定 > 一般 > ログイン項目** に EnterRemap を追加(常駐化)
3. 起動: `open ~/Applications/EnterRemap.app`

注意: ad-hoc署名のため、再ビルド後はアクセシビリティ許可の再付与
(一度削除して再追加)が必要になる場合がある。

## 仕組み

`CGEventTap` でkeyDownイベントを監視し、前面アプリが許可リストにある場合のみ
Enter(keycode 36)のmodifier flagsを書き換える。IMEが生成するイベントは
`eventSourceStateID != 1` となるため変換対象から除外し、日本語入力の変換確定
Enterを誤って改行/送信に変えない。

参考実装: https://qiita.com/nate3870/items/51b196de9a07717d3952

## Workflow

This project follows a Chat-then-Code workflow:

1. Architecture/design decisions are made in chat and written into `TASK.md`.
2. Claude Code implements against `TASK.md`, committing per task.
3. Completed task phases are archived under `docs/tasks/`.

See `CLAUDE.md` for details.
