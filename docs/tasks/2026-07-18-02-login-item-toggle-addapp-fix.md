# TASK: Open at Loginトグル化 & Add Custom Appパネル修正（Phase 11）

## 背景
2件の積み残し・不具合対応。

1. 「Open at Login」チェックボックス方式への変更は、以前の要望として
   出ていたがPhase 10のTASK.mdに含め忘れており未実装のまま。
   現状は「Open Login Items Settings...」（外部設定画面を開くだけ）
2. Phase 10で実装したAdd Custom Appパネルが、直接入力・
   ドラッグ&ドロップの両方とも機能していない（動作しない状態で
   実質的に壊れている）

## 要件

### 1. Open at Loginをチェックボックス方式に変更
- 「Open Login Items Settings...」（外部設定画面を開くリンク）を廃止する
- 代わりに「Open at Login」というチェックマーク付き `NSMenuItem` を追加し、
  クリックでトグルする
- `SMAppService.mainApp.register()` / `SMAppService.mainApp.unregister()`
  （macOS 13+）を使い、アプリ内で完結させる
- 起動時に `SMAppService.mainApp.status` を見て、実際の登録状態と
  メニューのチェック状態を同期させる（外部からログイン項目設定を
  操作された場合とのズレを防ぐ）

### 2. Add Custom Appパネルの不具合修正
- 直接入力・ドラッグ&ドロップの両方が機能しない原因を調査し修正する。
  確認観点の例（原因はこれらに限らないため、実際に手を動かして特定すること）:
  - `NSTextField` の `isEditable` / `isSelectable` / `isEnabled` が
    意図せず false になっていないか
  - パネル（`NSPanel`）が `becomesKeyOnlyIfNeeded` 等の設定により
    キーウィンドウになれず、テキストフィールドがフォーカスを
    受け取れていないか
  - ドラッグ&ドロップ側で `registerForDraggedTypes` が正しい
    `NSPasteboard.PasteboardType`（`.fileURL` 等）で呼ばれているか、
    `draggingEntered` / `performDragOperation` が実装され戻り値が
    正しいか
  - ビュー階層上、ドロップを受けるべきビューが実際にドラッグイベントを
    受け取れる状態か（他のビューに覆われていないか等）
- 入力欄に placeholder テキストを追加する:
  `"Input bundle identifier or drag and drop an app"`
  （文言は多少の調整は可。意味が伝わればよい）
- 修正後、以下を実機で確認する:
  - テキストフィールドに直接bundle IDを入力して追加できること
  - `.app` をドラッグ&ドロップして自動でbundle IDが入力されること
  - placeholderが表示されていること

## 非対象
- IME判定・AXRole判定・KeypadEnrollトグル等、他ロジックの変更
