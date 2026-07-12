# TASK: IME判定をAccessibility APIベースに変更（Google日本語入力対応）

## 背景
Phase 1（docs/tasks/2026-07-12-enter-remap-multiapp.md）で実装した
eventSourceStateID判定（!= 1 ならIME由来としてパススルー）は、
Apple標準日本語入力では機能するが、Google日本語入力では機能しない。
Google日本語入力では変換確定のEnterが物理Enterと同じ
sourceStateIDを持つ（＝CGEventTapレベルで区別不能）ためと推測される。

イベント由来のヒューリスティックをやめ、「今まさに変換中（未確定文字列が
存在する）かどうか」を状態として直接確認する方式に切り替える。

## 要件
1. Enter押下時、フォーカス中のUI要素をAccessibility API（AXUIElement）で取得し、
   未確定（marked/composing）テキストの有無を判定する
   - フォーカス要素の取得: AXUIElementCreateSystemWide +
     kAXFocusedUIElementAttribute
   - 判定候補（上から順に検証し、確実に動くものを採用）:
     a. kAXSelectedTextMarkerRange / marked text系属性（要素が対応していれば）
     b. NSTextInputContext関連の状態が外部から取れるか調査
     c. TISCopyCurrentKeyboardInputSource で現在のIMEを特定し、
        補助情報として使えるか調査
2. 変換中（未確定文字列あり）→ Enterをそのままパススルー（IME確定に使わせる）
   非変換中 → Phase 1と同じリマップ（Enter→Shift+Enter、Cmd+Enter→Enter）
3. 判定はEnter/Cmd+Enterキーイベント時のみ実行（全キーで叩かない）。
   レイテンシを計測し、体感遅延（目安: 10ms超）があれば報告する
4. Google日本語入力とApple標準日本語入力の両方で動作確認する
   - 確認項目: 変換確定Enter / 送信Cmd+Enter / 改行Enter / Shift+Enter
5. 対象アプリ許可リスト、tapDisabledByTimeout再有効化などPhase 1の
   その他のロジックは変更しない

## 調査で行き詰まった場合
Electron系アプリ（Claude等）はAX属性の対応が不完全な可能性がある。
marked text属性が取得できない場合は、代替案（例: kAXSelectedTextAttribute の
変化観察、IME on/off状態 + 直前のキー入力履歴の組み合わせ）を検討し、
実装前に方針を docs/ 配下にメモとして残すこと。

## 非対象
- Web版（ブラウザ）対応
- 許可リストの変更

## インストール先の変更（合わせて対応）
- build.sh のインストール先を ~/Applications から /Applications に変更する
  （admin アカウントなら sudo 不要）
- CLAUDE.md の Conventions に「Install target: /Applications」を追記する