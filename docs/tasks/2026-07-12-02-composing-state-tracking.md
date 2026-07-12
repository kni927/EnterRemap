# TASK: 変換状態トラッキングによるGoogle IME確定Enter対応（Phase 3）

## 背景
Phase 2のウィンドウ検出方式は、Google日本語入力で「Spaceで変換した直後」に
穴がある。Spaceで変換するとサジェストウィンドウが閉じ、候補ウィンドウは
2回目のSpaceまで表示されないため、この間のEnterは「非変換中」と誤判定され
Shift+Enterに変換される。Google IMEは変換中のShift+Enterを無視するため、
確定Enterが効かない（無視される）症状となる。

実測チェックリスト（docs/2026-07-12-ime-detection-notes.md 末尾）:
- [△] 変換確定Enter（かな入力→Space変換→Enter）: Enterが無視される
- [✔] サジェストウィンドウ表示中のEnter確定
- [✔] その他の項目

## 方針
画面上のウィンドウという間接証拠ではなく、キーイベント履歴から
「変換セッション中か」を状態機械としてトラッキングする。

## 要件
1. CGEventTap で対象アプリ前面時の全keyDownを観察し（変換はしない）、
   composing状態を管理する:
   - 開始: TISゲートが日本語入力モード、かつ文字を生成するキー
     （英字・数字・記号等）の押下
   - 終了: Enterパススルー実行時 / Escape / フォーカス・前面アプリ変更 /
     マウスクリック / Cmd系ショートカット
   - Backspace: 入力文字カウントを保持しデクリメント、0になったら
     composing解除（カウント方式が過剰なら、Backspace連打時の
     誤判定リスクを許容してシンプルな実装でも可。トレードオフをメモに残す）
2. Enter/Cmd+Enter時の判定順を再構成:
   - eventSourceStateID != 1 → パススルー（Apple IME安全網、変更しない）
   - TISゲート: 非日本語モード → 即リマップ（現状維持）
   - composing == true → パススルー + composing解除
   - ウィンドウ検出（Phase 2の本命）は補強シグナルとして残す
3. 誤判定の倒し方は現状踏襲: 迷ったらリマップ側
   （誤送信より誤改行の方が実害が小さい）
4. 動作確認（Google/Apple両IME、チェックリスト形式でメモに追記）:
   - Space変換→Enter確定（今回の本丸）
   - Space2回→候補ウィンドウからEnter確定
   - かな入力→無変換Enter確定
   - 確定後の通常Enter（改行になること）
   - Cmd+Enter送信 / Shift+Enter改行
   - マウスクリックで確定した直後のEnter（改行になること）
   - 変換中にEscapeで取り消し→Enter（改行になること）
5. レイテンシ: 全keyDown観察が加わるため、通常タイピングへの
   影響を確認（観察パスは判定なしの軽量処理にすること）

## 既知の限界（許容する）
- マウスクリック以外の暗黙確定（一部の関数キー等）は取りこぼす可能性がある。
  発見したら known-issues 相当としてメモに記録する

## 非対象
- 許可リストの変更、Web版対応

## Conventions追記（合わせて対応）
- CLAUDE.md に docs のファイル名規則を追記:
  `YYYY-MM-DD-NN-<slug>.md`（NNは同日内の2桁連番、01始まり）
- 既存の docs/2026-07-12-ime-detection-notes.md を
  docs/2026-07-12-01-ime-detection-notes.md にリネームする
