# TASK: Add Custom Appパネルの再構築（既知良好版起点 + 削除機能）

## 背景
Phase 10でドラッグ&ドロップ対応のため手作りNSWindowに書き換えて以降、
テキスト入力・placeholder・D&D結果のいずれも画面に描画されない
リグレッションが発生し、NSAlert方式へ戻しても再現した（詳細は
docs/tasks/ の関連アーカイブおよびdocs/KNOWN_ISSUES.md参照）。
根本原因は特定できていない（CGEventTap関与の可能性を示唆する
実験結果はあるが、検証未完了のまま作業を中断している）。

この状態でさらにデバッグを重ねるより、確実に動作していた実装まで
戻して再出発する。加えて、現状「追加はできるが削除できず増える一方」
という機能不足も解消する。

## 方針
1. git履歴から、Add Custom Appパネルが正常動作していた最後の実装
   （Phase 9、NSAlert方式、D&D機能追加前）を特定する。
   `docs/tasks/` のアーカイブとgit logを突き合わせて該当コミットを
   確認すること
2. リポジトリ全体をそのコミットに戻すのではなく、Add Custom App
   パネルに関するコード（該当メソッド・プロパティ・関連クラス）
   *のみ* をその時点の実装に置き換える。bundle ID変更・
   KeypadEnterトグル・Open at Login・公証方式変更など、Phase 10/11で
   加わった他の変更は維持すること
3. 置き換え後、まずビルドして実機で「直接入力・placeholder表示・
   Addでの登録」が動くことを確認する（この時点でD&Dは無くてよい）。
   ここで動作確認が取れるまで、次のステップに進まないこと

## 要件（動作確認が取れた後に実施）

### A. 削除機能の追加
- 登録済みのカスタムアプリ（プリセット以外、`loadCustomBundleIDs()`
  相当で管理しているもの）を一覧表示し、個別に削除できるUIを追加する
- 実装形態は自由（例: Target Appsサブメニュー内でカスタムアプリの
  項目に削除用の隣接メニュー、または一覧+削除ボタンを持つ別ウィンドウ等）
- 削除後、UserDefaultsへの永続化と許可リスト（ALLOWED_BUNDLE_IDS）
  からの除去、メニューの再構築（rebuildSubmenu等）を行う

### B. ドラッグ&ドロップの再導入（慎重に）
- Aの削除機能が動作確認済みになった後に着手する
- 既知良好版（NSAlert方式）のaccessoryViewに、ドロップ領域を追加する
- 追加後、直接入力の動作に影響が出ていないか（表示・placeholderが
  引き続き機能するか）を必ず確認してから完了とする
- もし今回もD&D追加によって表示に異常が出た場合は、深追いせず
  D&Dなしの状態（直接入力のみ）で確定し、D&D自体は
  `docs/KNOWN_ISSUES.md` に「原因不明・再現条件: D&D追加時に
  テキストフィールド描画が壊れる」として記録し、別タスクに切り出すこと

## 検証チェックポイント（各ステップ後に必須）
- 直接入力した文字が画面に表示されるか
- placeholderが表示されるか
- Addで正しく登録されるか
- （B着手後）ドロップしたアプリのbundle IDが表示・登録されるか
- （A完了後）削除が反映され、再起動後も消えたままか

## 非対象
- IME判定・AXRole判定・KeypadEnterトグルなど他ロジックの変更
- CGEventTap関与の根本原因調査そのもの（時間がかかりすぎる場合は
  Known Issue化して打ち切ってよい）

## Implementation Result

**Status:** Completed

### Changes

すべて `main.swift` の `TargetAppsMenuController` 周辺のみ。他のPhase 10/11
変更（bundle ID `com.kni.EnterRemap`、KeypadEnterトグル、Open at Login、
公証方式）は無改変を確認済み。コミットは検証済みマイルストーンごとに分割:

- **既知良好版の復元**（commit `fdc6502`）: リグレッション源は Phase 10
  （`686067f`）でD&Dのため手作りNSWindow化した箇所と特定。Add Custom App
  パネルのコード *のみ* を Phase 9（`b5756d0`、素のNSAlert + NSTextField、
  D&Dなし）にバイト単位一致で置換し、`AppDropView` を削除。
- **削除機能A**（commit `2aa99f4`）: Target Appsサブメニューに、カスタム
  アプリが1件以上あるとき「Remove Custom App」サブメニューを追加。選択で
  `CustomBundleIDs` と `ALLOWED_BUNDLE_IDS` の両方から除去して永続化し
  `rebuildSubmenu()`。プリセットはトグル（無効化）のみで削除不可。
- **D&D再導入B**（commit `f0a3371`）: NSTextFieldサブクラスにドロップ
  ハンドラを実装する方式は、フィールドエディタ（NSTextView）がドロップを
  横取りするため不成立（`draggingUpdated`までは来るが
  `prepareForDragOperation`/`performDragOperation`が呼ばれないことを
  デバッグprintで確定）。代わりに、素のNSTextFieldの前面に透明な
  `DropOverlayView` を重ねてドロップを受ける方式を採用。`hitTest`→`nil`で
  クリック透過（ドラッグ先ヒットテストはマウスhitTestと独立のためドロップは
  受けられる）、`performDragOperation`で `Bundle(url:)?.bundleIdentifier` を
  抽出→`onDrop`でフィールドに設定→`true`返却でデフォルトのパス挿入を抑止。

### Verification

- Build: 各ステップで `./build.sh` 成功。
- Automated verification: 削除機能の永続化round-trip（add→remove→再読込で
  両ストアから消え、他カスタム/プリセット無影響、全削除でリスト空）を
  スタンドアロンハーネスで確認（別UserDefaultsドメイン使用）。
- Manual verification（project owner、実機、各増分ごと）:
  - 復元: 直接入力の表示・placeholder表示・Add登録 → OK
  - A: Removeサブメニュー出現・クリックで削除・再起動後も消えたまま → OK
  - B: 段階検証（registerForDraggedTypesのみ→draggingEntered→
    performDragOperation→オーバーレイ方式）を経て、最終的に
    placeholder表示・直接入力・Add登録・`.app`ドロップでbundle ID
    （生パスでない・二重挿入なし）表示&登録・オーバーレイがクリック/
    入力を妨げない、をすべて確認 → OK
- Not performed: なし（各チェックポイントを実機確認済み）。

### Remaining Issues

- None。

### Follow-up Suggestions

- 今回「Phase 10のD&D手作りNSWindow化がリグレッション源」「オーバーレイ方式で
  D&Dを両立」という恒久的な技術判断を行った。プロジェクトが育てば
  `docs/DECISIONS.md` に記録する価値がある（本タスクでは新規作成を見送り、
  アーカイブに記録）。
