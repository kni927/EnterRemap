# TASK: UI仕上げ・公証・GitHub Release公開（Phase 8 / v1.5.1）

## 背景
リリース前の最終仕上げ。UI改善2件、アプリアイコンの組み込み、
公証(notarization)、GitHub Releaseでの公開まで一気に行う。

## 要件

### 1. AppIcon統合
- `Assets/AppIcon.png` は配置済み。これを `.icns` に変換し
  （`iconutil` 等で複数解像度の `.iconset` を生成してから変換）、
  build.sh でアプリバンドルに組み込む
- Info.plist の `CFBundleIconFile` を設定する
- ビルド後、Finder/メニューバーで実際にアイコンが表示されることを確認する

### 2. Target Appsのサブメニュー化
- 現行の独立 `NSWindow` + チェックボックスUIを廃止し、
  メインメニューの「Target Apps」を `NSMenu` のサブメニューに変更する
- サブメニュー内の各項目はプリセットアプリ（Claude / ChatGPT新統合版 /
  ChatGPT Classic / Gemini / Discord）をチェックマーク付き `NSMenuItem`
  として並べ、クリックで即トグル（チェックON/OFF）→ UserDefaults反映
- bundle ID手動追加の入力欄は、サブメニュー内に "Add Custom App..." 的な
  項目を置き、クリックしたら簡易的な入力ダイアログ（`NSAlert` +
  `NSTextField` accessory view程度でよい）を出す形に置き換える
- Phase 7で作った `TargetAppsWindowController` は不要になるため削除する

### 3. メニュー項目にHideを追加
- 「Quit」の直前に「Hide EnterRemap」を追加する
- 標準の `NSApplication.hide(_:)` を使う（ショートカット cmd+H を
  割り当ててよい）

### 4. バージョン更新
- v1.5.1 に更新する（build.sh、Info.plist、README記載のバージョン表記等）

### 5. 公証(notarization)
- 既存のDeveloper ID証明書（cooViewerで使用しているもの）で署名する
- `xcrun notarytool submit` で公証申請する。認証は既存のKeychain
  Profile（cooViewerと同じものを使い回す想定。プロファイル名が
  不明な場合は `xcrun notarytool history --keychain-profile <name>`
  等で確認可能なら確認し、不明であれば作業を止めてMasterに確認する）
- 成功後 `xcrun stapler staple` でチケットをアプリバンドルに添付する
- `spctl -a -vv` で `accepted` になることを確認する
- build.sh に公証ステップを組み込み、以後のビルドで再利用できるようにする
  （既存のad-hoc署名ビルドとは別コマンド/フラグで切り替えられると尚良い）

### 6. 配布用zip作成
- 公証済み `.app` を `ditto -c -k --keepParent` 等でzip化する
  （notarization staple後にzip化すること。zip化してから公証すると
  stapleが正しく反映されないため順序に注意）
- ファイル名は `EnterRemap-v1.5.1.zip` 等、バージョンが分かる形にする

### 7. GitHub Release公開
- `gh release create v1.5.1` で公開する
- 公証済みzipをrelease assetとして添付する
- リリースノートは Phase 5〜8 の変更点（メニューバー化、AXRole判定、
  対象アプリ設定UI、Discord対応、公証対応など）を簡潔にまとめる

## 動作確認
- 新規ダウンロード想定で、Gatekeeperの警告なしに起動できること
  （公証済みのため「開発元を確認できません」が出ない）
- メニューバーアイコンの見た目、Target Appsサブメニューの動作、
  Hideメニューの動作
- 既存のIME判定・AXRole判定にリグレッションがないこと（簡易確認でよい）

## 非対象
- App Store配布
- Sparkle等の自動アップデート機構
