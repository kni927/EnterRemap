# IME変換中判定の調査メモ(Phase 2)

日付: 2026-07-12
対象タスク: IME判定をAccessibility APIベースに変更(Google日本語入力対応)

## 判定候補の検証結果

### a. AX marked text系属性(kAXSelectedTextMarkerRange等)

- 対象アプリ(Claude / ChatGPT / ChatGPT Classic / Gemini)は全てElectron
  (Chromium)製。ChromiumはIMEのcomposition(未確定文字列)をレンダラ内部の
  IMEパイプラインで処理しており、**AXツリーにmarked textを公開しない**
  (WebKit系の`AXSelectedTextMarkerRange`はSafari/WebKit専用のプライベート属性。
  Chromiumに相当実装はない)。
- 開発シェル(Claude Code)にはアクセシビリティ権限がなく
  (`AXIsProcessTrusted: false`、`AXUIElementCopyAttributeValue`は
  kAXErrorAPIDisabled=-25211)、実機での属性列挙による裏取りは本環境では不可。
- 対応: 実装には`AXHasMarkedText`(Bool)が取得できた場合のみ信頼する
  プローブを残し、加えて **`--probe` 診断モード** をバイナリに内蔵した。
  アクセシビリティ権限を持つ本体アプリとして実行すれば、変換中に
  フォーカス要素の全AX属性を実測できる。将来属性が見つかればここを昇格する。

### b. NSTextInputContextの外部取得

- `NSTextInputContext`はAppKitのin-process APIであり、他プロセスの
  入力コンテキスト状態を外から照会する公開手段はない。**不採用**。

### c. TISCopyCurrentKeyboardInputSource(補助情報)

- 実測: 温間 **約0.01ms**。現在の入力ソースID/inputModeIDが取れる。
- `kTISPropertyInputModeID`が`nil`(ABC等のキーボードレイアウト)または
  `…Roman`(Google日本語入力の英数モード)なら変換は起こり得ない。
  **高速ゲートとして採用**(これだけでは「変換中」までは分からない)。

## 採用した方式(多層判定)

Enter/Cmd+Enter押下時のみ、以下を順に評価する:

1. **eventSourceStateID != 1 → 変換中扱い(パススルー)**
   Phase 1の判定を安全網として残す。Apple標準日本語入力の確定Enterは
   この判定で正しく検出できることが実運用で確認済みであり、完全撤去すると
   Apple IME側がリグレッションする(ライブ変換の確定時は候補ウィンドウが
   出ないため、後段のウィンドウ検出では拾えない)。タスク文言の
   「イベント由来ヒューリスティックをやめる」からの意図的な逸脱。
2. **TISゲート**: inputModeIDがnilまたはRoman → 非変換中 → リマップ。
   (~0.01ms。日本語モードでない限り後段のコストは発生しない)
3. **AX marked text**: フォーカス要素(AXUIElementCreateSystemWide経由)に
   `AXHasMarkedText`があればその値を採用。Electronでは現状取得不可の見込み。
4. **IME UIウィンドウ検出(フォールバック、本命)**:
   `CGWindowListCopyWindowInfo`(実測 約1.7ms)で、稼働中のIMEプロセス
   (bundle IDに`inputmethod`を含む。Google日本語入力では
   `com.google.inputmethod.Japanese.Renderer`)が所有する画面上ウィンドウが
   あれば変換中とみなす。Google日本語入力はデフォルトで入力中に
   サジェストウィンドウ、変換中に候補ウィンドウを表示するため、
   変換確定Enterの時点ではRenderer所有ウィンドウが存在する。
5. どれにも該当しない → 非変換中 → リマップ。

デフォルトを「非変換中(リマップする)」に倒す理由:
誤って「変換中」と判定するとEnterが素通りし、対象アプリでは**誤送信**になる
(本ツールが防ぎたい事故そのもの)。逆方向の誤判定(変換中なのにリマップ)は
IMEにShift+Enterが渡るだけで、送信事故にはならない。

## 既知の限界・エッジケース

- Google日本語入力で**サジェスト表示をオフ**にしていると、無変換のかな入力を
  Enterで確定する際にウィンドウが存在せず、リマップが走る(IMEには
  Shift+Enterが渡る)。誤送信にはならないが確定挙動がキーマップ依存になる。
- 入力ソース切替直後の約1秒はモード表示バブル(Renderer所有)が画面に残り、
  その間のEnterは変換中扱いでパススルーされる。切替直後に何も入力せず
  Enterを押すケースのみ影響(稀)。
- IME設定画面等のウィンドウが開いている間も「変換中」と誤判定し得る
  (日本語モード時のみ)。実害は小さいと判断。

## レイテンシ実測(このマシン、2026-07-12、`EnterRemap --probe`)

| 処理 | 温間 | 初回(コールド) |
|---|---|---|
| TIS入力ソース照会 | 0.02〜0.03ms | ~70ms |
| AXフォーカス要素取得 | 0.3〜5.4ms | ~53ms |
| CGWindowList照会 | 3.5〜4.0ms | ~27ms |
| 合計(最悪経路: 日本語モードでEnter) | **4〜9ms(目安10ms以内)** | ~150ms |

- コールドスタートの~150msはプロセス初回呼び出しのみ。デーモン起動時に
  プリウォーム呼び出しを入れて最初のEnterに乗らないようにした。
- 英数モード時はTISゲートで即決(~0.03ms)するため実質ゼロ。
- 温間の最悪値9msは目安10msに近い。AX照会は権限なし環境での計測のため、
  権限付与後に `--probe` で再計測し、体感遅延があれば報告すること。

## 動作確認チェックリスト(要手動確認)

Google日本語入力 / Apple標準日本語入力それぞれで、対象アプリにて:

- [ ] 変換確定Enter(かな入力→変換→Enter)が確定のみで送信されない
- [ ] 無変換確定Enter(かな入力→そのままEnter)が確定のみで送信されない
- [ ] 非変換中のEnterが改行になる
- [ ] Cmd+Enterで送信される
- [ ] Shift+Enterが改行のまま
- [ ] (Google)サジェストウィンドウ表示中のEnter確定
- [ ] 英数モードでのEnter改行に遅延を感じない

---

# Phase 3 追記: 変換状態トラッキング(2026-07-12)

## 背景

Phase 2のウィンドウ検出は、Google日本語入力で「Spaceで変換した直後」
(サジェストウィンドウが閉じ、候補ウィンドウは2回目のSpaceまで出ない区間)に
穴があり、確定Enterがリマップされて無視される症状が実測で確認された。

## 実装した状態機械

対象アプリ前面時の全keyDownを観察し(変換はしない)、
`composingKeyCount` で変換セッションを追跡する:

- **開始/加算**: 日本語入力モード(TISゲート)で、レイアウトレベルで
  印字文字を生成するキー(`keyboardGetUnicodeString`で判定。
  空白・制御文字・矢印/ファンクションキー領域0xF700-0xF8FFを除外)、
  かつCmd/Ctrl修飾なし、かつIME合成イベント(sourceStateID != 1)でない
- **減算**: Backspaceでデクリメント、0でcomposing解除
- **解除(リセット)**: Enterパススルー実行時 / Escape / Cmd系ショートカット /
  マウスクリック(left/right/other) / 前面アプリ変更 /
  Apple IME確定Enter検出時 / 入力モードが非日本語になったEnter時

Enter/Cmd+Enter時の判定順(要件2どおり):

1. `eventSourceStateID != 1` → パススルー+解除(Apple IME安全網)
2. TISゲート: 非日本語モード → 解除+リマップ
3. `composingKeyCount > 0` → パススルー+解除
4. 補強: `AXHasMarkedText` / IME UIウィンドウ検出 → パススルー
5. リマップ

## Backspaceカウント方式のトレードオフ(要件1の注記対応)

キーストローク数≠未確定文字数のため、カウントはずれる:

- ローマ字入力では「か」=2打鍵でカウント2だが、変換中のBackspaceは
  かな1文字(「か」全体)を消す → **カウントが過大に残る**。
  未確定文字列を全部Backspaceで消した後もcomposing扱いが残り、
  直後のEnterが1回だけパススルーされる(対象アプリでは送信になり得る)。
  発生条件は「かなを打つ→全部Backspaceで消す→直後にEnter」と狭く、
  マウスクリック/Escape/アプリ切替のいずれでも解除されるため許容した。
- 逆に「Backspace1回=1打鍵分」として引きすぎる方向のズレは
  起こらない(1打鍵1文字のかな入力ではズレ自体がない)。
- 実害が出る場合の改善案: Enter時にカウント>0でも補強シグナル
  (ウィンドウ検出)と突き合わせて棄却する、またはBackspaceで
  即時解除に倒す(その場合「一部削除→Enter確定」がリマップされる)。

## 既知の限界(Phase 3で許容)

- マウスクリック以外の暗黙確定(一部ファンクションキー、fn+Delete
  (前方削除、keycode 117)等)は取りこぼす可能性がある。
  発見したら本メモに追記すること。
- Tabキー等キーボードのみでのフォーカス移動は解除トリガーにならない
  (クリック/アプリ切替は捕捉)。
- 入力ソース切替直後のモード表示バブル(約1秒)による誤パススルーは
  Phase 2から変わらず残る(補強シグナル側の性質)。

## レイテンシ(要件5)

観察パス(非Enterキー、温間実測):

| 処理 | 実測 |
|---|---|
| frontmostApplication照会 | ~0.001ms |
| keyboardGetUnicodeString | ~0.0004ms |
| TIS照会(文字生成キーのみ) | ~0.01-0.03ms |
| **観察パス合計** | **~0.03ms/keyDown** — タイピングへの影響なし |

Enter時の最悪経路はPhase 2と同じ(4〜9ms、状態機械ヒット時はほぼゼロ)。

## 動作確認チェックリスト(Phase 3、要手動確認)

Google日本語入力 / Apple標準日本語入力それぞれで、対象アプリにて:

- [ ] Space変換→Enter確定(今回の本丸: Enterが無視されず確定される)
- [ ] Space2回→候補ウィンドウからEnter確定
- [ ] かな入力→無変換Enter確定
- [ ] 確定後の通常Enter(改行になること)
- [ ] Cmd+Enter送信 / Shift+Enter改行
- [ ] マウスクリックで確定した直後のEnter(改行になること)
- [ ] 変換中にEscapeで取り消し→Enter(改行になること)
- [ ] 通常タイピングに遅延を感じないこと
