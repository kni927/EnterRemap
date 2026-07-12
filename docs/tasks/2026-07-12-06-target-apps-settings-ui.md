# TASK: 対象アプリ設定UIの追加（Phase 7）

## 背景
現状、対象アプリ（許可リスト）は `ALLOWED_BUNDLE_IDS: Set<String>` として
main.swiftにハードコードされている。Discord（Enter送信、変更不可）のような
新しい対象アプリが今後も増える見込みのため、コード変更・再ビルドなしで
対象アプリを選択できるようにする。

## 対象アプリ候補の追加
- Discord: com.hnc.Discord
  （Discord PTB: com.hnc.DiscordPTB、Discord Canary: com.hnc.DiscordCanary
   も存在するが、Masterが使っているのは正式版のみなので優先度低）

## 要件
1. 許可リストを `UserDefaults` に永続化する
   - 初回起動時、現行のハードコード値（Claude / ChatGPT新統合版 /
     ChatGPT Classic / Gemini）をデフォルトとして書き込む
   - Discordはプリセット候補として一覧に追加するが、初期状態は
     OFF（Masterが明示的にONにする）
2. メニューバーメニューに設定UIを追加する
   - 既存の Pause / Resume / Quit に加えて「Target Apps...」のような
     項目を追加
   - シンプルなチェックボックスリスト（プリセット4〜5個 + Discord）を
     ウィンドウまたはサブメニューで表示し、チェックのON/OFFで
     即座に許可リストへ反映する（再起動不要）
   - 実装形態は NSWindow + NSTableView（チェックボックス列）でも、
     NSMenu のサブメニュー項目にチェックマーク付きで並べる形でもよい。
     実装コストが低い方を選んでよい
3. 任意のbundle IDを手動追加できる入力欄を設ける
   （プリセットにないアプリへの将来の拡張のため）
4. 起動オプション（コマンドライン引数）による対象アプリ指定は不要
   （設定UIのみで完結させる）
5. 許可リストの変更はIME判定・AXRole判定など既存ロジックには影響しない
   （前面アプリ判定の参照先が定数からUserDefaults読み出しに変わるだけ）

## 動作確認
- Discordをチェックした状態で、Discordのメッセージ入力欄で
  Enter→改行、Cmd+Enter→送信になること
- チェックを外した対象アプリでは、リマップが機能しない
  （通常のEnter動作に戻る）こと
- 設定変更が再起動後も保持されること

## 非対象
- IME判定・AXRole判定ロジックの変更
- Discord固有の癖への個別対応（今回はEnterRemap既存ロジックの
  横展開のみ。動作確認で問題が出れば別タスクとする）
