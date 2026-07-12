# TASK: 単一行テキストフィールドでのEnter誤動作修正（Phase 6）

## 背景
Claude Desktop上でMarkdownファイルをダウンロードする際、Save Asダイアログ
（ファイル名入力欄）でEnterを押しても保存されず、代わりにファイル名の
選択範囲が広がる（拡張子まで選択される）という誤動作が発生した。

原因と推測される仕組み:
- Save Asダイアログは呼び出し元アプリ（com.anthropic.claudefordesktop）の
  シート/パネルとして表示されるため、frontmostアプリの判定は
  Claudeのままとなり、許可リストにヒットしてEnterがリマップされ続ける
- ダイアログのファイル名欄は単一行のAXTextField。本来Enterは
  「デフォルトボタン（Save）をクリックする」動作だが、これが
  Shift+Enterにリマップされてしまい、テキストフィールド内では
  無意味な動作（選択範囲の拡張等）になっていたと考えられる
- チャット入力欄（複数行のAXTextArea相当）では現状のリマップ
  （Enter→改行、Cmd+Enter→送信）が正しい挙動であり、この使い分けが
  できていないのが根本原因

## 方針
前面アプリのbundle ID判定に加えて、フォーカス中のUI要素のAXRoleを見て、
単一行入力（ファイル名欄、検索欄、通常のテキストフィールド等）では
リマップを行わず、Enterをそのまま素通しする。

## 要件
1. Enter/Cmd+Enter押下時、AXUIElementでフォーカス中の要素のroleを取得する
   - kAXFocusedUIElementAttribute → kAXRoleAttribute
2. 判定ロジック:
   - role が AXTextField（単一行）→ リマップせず素通し
     （Enterはデフォルトボタン起動、Cmd+Enterも素通しでよい）
   - role が AXTextArea等の複数行入力 → 既存のリマップロジックを適用
   - roleが取得できない場合（Electron系でAX非対応等）→ 現状維持
     （既存の許可リスト＋IME判定ロジックのみで判定、フォールバック）
3. 既存のIME判定（sourceStateID安全網、TISゲート、composing state、
   ウィンドウ検出）は、AXTextArea判定時のみ従来通り適用する
4. 動作確認:
   - Claude DesktopでのMarkdown等のSave Asダイアログ（ファイル名欄）で
     Enterによる保存ができること（今回の本丸）
   - チャット入力欄でのEnter/Cmd+Enter/日本語IME確定の既存動作に
     リグレッションがないこと
   - 対象アプリ内の他の単一行入力（検索ボックス等）でEnterが
     素通しされること（気づいた範囲でよい）

## 非対象
- メニューバーアイコン化（Phase 5）とは独立。両方合流してよい
- 許可リストの変更
