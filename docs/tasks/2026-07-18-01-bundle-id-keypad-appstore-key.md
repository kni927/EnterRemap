# TASK: KeypadEnterトグル・Add Custom App改善・bundle ID変更・公証方式変更（Phase 10）

## 背景
複数の改善要望をまとめて対応する。特にbundle ID変更と公証方式変更は
実施タイミングが早いほど影響が小さいため、このタイミングで行う。

## 要件

### 1. テンキーEnter(KeypadEnter)のリマップ有無をメニューでトグル
- 現状、`kVK_ANSI_KeypadEnter`(76)はリマップ対象外で素通しされている
  （アプリのデフォルト動作＝多くの場合送信、になる）
- Chrome拡張（Chat AI Ctrl+Enter Sender）はテンキーのEnterも
  送信させない（リマップ対象に含める）挙動になっている。これに揃えたい
- メニューバーに「Remap Keypad Enter」のようなチェックマーク付き
  `NSMenuItem` を追加し、ON/OFFで以下を切り替える:
  - OFF（デフォルト、現状維持）: KeypadEnterは素通し
  - ON: KeypadEnterもkVK_Returnと同じ判定パス
    （IME判定・AXRole判定含む）でリマップする
- 設定はUserDefaultsに永続化する

### 2. Add Custom Appダイアログの改善
- 現状のターミナルコマンド例（`mdls`/`osascript`）の表示をやめる
- 代わりに以下2つの入力手段を提供する:
  a. bundle IDを直接入力するテキストフィールド（現状維持）
  b. .appファイルをドラッグ&ドロップできるようにし、ドロップされた
     `.app`から`Bundle(url:)?.bundleIdentifier`で自動抽出して
     入力フィールドに反映する
- 実装形態: NSAlertのaccessory viewでドラッグ&ドロップは制約が多いため、
  シンプルな`NSPanel`（もしくは既存のような軽量ウィンドウ）に
  `NSTextField`(手入力可) + ドロップ領域を持たせる形でよい

### 3. bundle IDの変更
- `com.local.enter-remap` → `com.kni.EnterRemap` に変更する
  （Info.plist の `CFBundleIdentifier`、署名時の識別子、
  build.sh内の参照箇所すべて）
- 影響を明記してREADME(日英)に一言注記を追加する:
  - アクセシビリティ権限の再付与が必要
  - Target Appsの許可リスト等の設定（UserDefaults）は
    旧bundle ID時代のものが引き継がれない（初回シードからやり直し）
  - ログイン項目の再登録が必要
- 旧バージョンからのアップグレードパスは今回設けない
  （READMEに「上記の再設定が必要」と書けば足りる）

### 4. 公証方式をKeychain ProfileからApp Store Connect APIキー方式に変更
- 既存のKeychain Profile（`EnterRemap-notary`）方式から、
  `.p8` APIキーを使った方式に変更する（cooViewerと同方式に統一）
- `.p8` の配置場所は `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
  を前提とする（**リポジトリには絶対にコミットしない**。.gitignoreに
  念のため `*.p8` を追加する）
- `xcrun notarytool submit --key <path> --key-id <KEY_ID> --issuer <ISSUER_ID>`
  形式に build.sh を更新する（KEY_ID・ISSUER_IDは環境変数か
  build.sh実行時の引数で渡せるようにし、値自体はコードに埋め込まない）
- 変更後、実際に公証が通ることを確認する

## 実施順序の推奨
bundle ID変更（3） → 公証方式変更（4）→ 動作確認 → 機能追加（1, 2）
の順が事故が少ない（識別子・署名周りを先に固めてから機能を足す）。
ただしこだわりがなければ実装しやすい順でよい。

## 動作確認
- KeypadEnterトグルON/OFF双方で意図通りの挙動になること
- Add Custom Appでドラッグ&ドロップ・直接入力の両方が機能すること
- bundle ID変更後、ビルド・公証・署名確認（`spctl -a -vv`）が通ること
- 新しいbundle IDでアクセシビリティ権限を再付与し、通常動作すること

## 非対象
- IME判定・AXRole判定ロジックの変更
- 既存許可リスト設定の自動移行
