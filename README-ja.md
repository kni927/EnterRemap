# EnterRemap

[English](README.md) | 日本語

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

## 異常終了通知(v1.3)

launchd + KeepAliveによる自動再起動は、`killall`での意図的な終了時にも
復活してしまう副作用があるため見送り、通知による対症療法を採用している。
UserNotifications frameworkで以下のタイミングでmacOS通知を出す:

- イベントタップが無効化され、既存の自動再有効化ロジックでも復帰できなかった場合
- SIGTERM/SIGINT/SIGHUPを捕捉できた場合(`killall`による意図的終了と
  区別しない。「止まったことに気づける」ことが目的)

通知の許可(通知権限)が必要。初回起動時に自動でリクエストされるが、
拒否した場合や、通知が一度も届かない場合は
**システム設定 > 通知 > EnterRemap** で許可されているか確認すること。
診断用に `EnterRemap --test-notification` でテスト通知を1回送れる。

**既知の制限**: この機能の実機での通知到達確認は、開発時の環境
(未公証のアプリに対してmacOSが通知権限要求自体を拒否する状態)では
行えなかった。詳細は [known-issues.md](known-issues.md) を参照。

## 単一行テキストフィールドの除外(v1.3.1)

Save Asダイアログのファイル名欄のような単一行入力(AXTextField)は、
呼び出し元アプリ(例: Claude Desktop)のシート/パネルとして表示されるため
frontmostアプリの判定だけでは対象アプリと区別できず、リマップの対象に
なってしまっていた。単一行フィールドではEnterは「デフォルトボタンの起動」
であり改行ではないため、フォーカス中の要素のAXRoleを見て以下のように
判定する:

- `AXTextField`(単一行) → リマップせず素通し(Cmd+Enterも素通し)
- `AXTextArea`等・role取得不可(Electron等) → 既存のリマップ+IME判定を適用

## IME判定の仕組み(v1.2)

対象アプリ前面時のkeyDownを観察して「変換セッション中か」を状態機械で
トラッキングし、Enter押下時に多層チェックで判定する
(詳細: [docs/2026-07-12-01-ime-detection-notes.md](docs/2026-07-12-01-ime-detection-notes.md))。

1. `eventSourceStateID != 1` → IME由来イベント(Apple標準日本語入力の確定Enter)
2. 現在の入力ソースが英数/非IME → 非変換中(TIS照会 ~0.01ms)
3. 変換状態トラッキング: 日本語モードでの文字キー入力で開始、
   Enter確定/Escape/クリック/アプリ切替/Cmd系ショートカットで解除 —
   Google日本語入力のSpace変換直後(候補ウィンドウ非表示区間)もカバー
4. 補強シグナル: フォーカス要素の `AXHasMarkedText`、
   IMEプロセス所有のオンスクリーンウィンドウ検出(~4ms)

観察パスは ~0.03ms/keyDown、Enter時の最悪経路でも10ms以内で体感遅延はない。

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

## 状態確認・終了

```bash
pgrep -l EnterRemap   # 動作確認
killall EnterRemap    # 終了(自動再起動はしない。ログイン項目に
                      # 登録されている場合は次回ログイン時に復帰)
open /Applications/EnterRemap.app   # 再起動
```

## 参考実装との差分

[参考にした記事](https://qiita.com/nate3870/items/51b196de9a07717d3952)の実装は
Claude単体・Apple標準の日本語入力(ライブ変換確定)のみが動作する前提で、
Google日本語入力は元々対象にしていない。本プロジェクトは以下の点を
拡張している(なぜ似たような実装を再度行っているのかの理由):

- 対象アプリをbundle ID許可リストで複数アプリ化(Claude / ChatGPT / Gemini)
- Google日本語入力でも正しく動作させるため、`eventSourceStateID`単独判定を
  やめ、TISゲート・AX/ウィンドウ検出・composing状態トラッキングの
  多層判定に拡張(Phase 2〜3、詳細:
  [docs/2026-07-12-01-ime-detection-notes.md](docs/2026-07-12-01-ime-detection-notes.md))
- 異常終了に気づけるようUserNotificationsによる通知を追加(Phase 4)

## Known Issues

- **IME候補ウィンドウのマウスクリック**: 変換候補が表示された状態で、
  上部の入力文字列部分をクリックすると選択状態が解除されて本来の挙動に戻るが、
  候補そのものをクリックすると選択状態が残ったままになる。次の入力自体は
  問題なく行えるため実害はほぼなく、そもそも変換確定をマウスで行うこと自体が
  稀なため、既知の限界として許容する。

## 参考実装・クレジット

CGEventTap + eventSourceStateID によるIMEセーフなEnterリマップの
基本アイデアは以下の記事による: https://qiita.com/nate3870/items/51b196de9a07717d3952

## Workflow

This project follows a Chat-then-Code workflow:

1. Architecture/design decisions are made in chat and written into `TASK.md`.
2. Claude Code implements against `TASK.md`, committing per task.
3. Completed task phases are archived under `docs/tasks/`.

See `CLAUDE.md` for details.
