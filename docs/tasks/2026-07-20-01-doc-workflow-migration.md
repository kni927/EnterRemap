# TASK: ドキュメント体系の新ワークフロー移行（housekeeping）

## 背景
プロジェクトのワークフロー定義を新テンプレート体系
（AGENTS.md + スリムなCLAUDE.md + docs/task-workflow.md +
docs/handover-template.md）に移行した。これらのファイル自体は
project ownerが既に配置済み。残りの整合性対応を行う。

## 前提（確認してから作業すること）
- repo rootに新しい `CLAUDE.md`（@AGENTS.mdをimportする形式）と
  `AGENTS.md` が配置されていること
- `docs/task-workflow.md`、`docs/handover-template.md` が存在すること

## 要件

### 1. known-issues.md の移動
- repo rootの `known-issues.md` を `docs/KNOWN_ISSUES.md` に移動する
  （git mvで履歴を維持）
- 内容はそのまま。ただし新体系の定義
  「unresolved, reproducible, and actionable problems」に照らして、
  既に解決済みの項目が残っていれば削除してよい（判断に迷うものは残す）

### 2. 参照の更新
- `known-issues.md` への参照（README.md / README-ja.md / docs配下 /
  コード内コメント等）をgrepで洗い出し、`docs/KNOWN_ISSUES.md` に更新する
- 旧CLAUDE.mdにのみ存在した記述（UI英語ルール、インストール先等）が
  新CLAUDE.mdに引き継がれていることを確認する（引き継がれているはず。
  漏れがあれば報告のみ行い、勝手に追記しない）

### 3. ディレクトリの準備
- `docs/tasks/` は既存。`docs/handovers/` はこのタスクでは作成不要
  （必要になったときに作成される運用でよい）

### 4. 完了処理
- 新しい docs/task-workflow.md の Task Completion 手順に従うこと
  （Implementation ResultをTASK.mdに追記 → docs/tasks/へアーカイブ →
  chatにCompletion Report）。このタスク自体が新ワークフローの
  最初の適用例となる

## 非対象
- README本文の内容変更（参照パスの更新のみ可）
- コード（main.swift / build.sh）の変更
- push（コミットまで。pushはproject ownerの指示を待つ）

## Implementation Result

**Status:** Completed

### Changes

- `known-issues.md` を `git mv` で `docs/KNOWN_ISSUES.md` へ移動（履歴保持）。
  内容は日本語のまま維持（AGENTS.md「既存の言語・スタイルを保持」に準拠）。
  唯一の項目「IME候補ウィンドウのマウスクリック挙動」は未解決かつ再現可能な
  許容済み制限であり、新定義 "unresolved, reproducible, and actionable" に
  合致するため削除せず維持。
- 参照更新: `docs/2026-07-12-01-ime-detection-notes.md` 内の
  マークダウンリンク `[known-issues.md](../known-issues.md)` を
  `[KNOWN_ISSUES.md](KNOWN_ISSUES.md)`（同一 docs/ ディレクトリ相対）に更新。
- 意図的に更新しなかった参照:
  - `docs/tasks/2026-07-12-02-*.md` / `docs/tasks/2026-07-12-05-*.md` の
    "known-issues" 言及は、過去タスクのアーカイブ（履歴記録）であり、
    かつライブなリンクではなく当時の状態を記述した散文のため、
    書き換えると履歴を改変することになるので保持。
  - `TASK.md`（本ファイル）内の参照はタスク説明自体のため対象外。
- 旧 CLAUDE.md の記述はすべて新体系（新CLAUDE.md / AGENTS.md /
  task-workflow.md）へ引き継がれていることを照合済み。漏れなし、追記なし。

### Verification

- Build: 未実施（docs のみの変更でコード非改変。build.sh / main.swift は不変）。
- Automated verification: `grep -rn "known-issues"` で残存参照を確認し、
  ライブリンクは ime-detection-notes.md の1件のみと特定・更新済み。
  移動後 `docs/KNOWN_ISSUES.md` の存在と `git mv` によるリネーム検出（R）を確認。
- Manual verification: 更新後リンクの相対パス（docs/ 内同一ディレクトリ）を
  目視確認。
- Not performed: アプリのビルド/起動確認（本タスクの範囲外）。

### Remaining Issues

- None（本タスク範囲内）。

### Follow-up Suggestions

- 新 CLAUDE.md の "Commands" 節に記載の notarize 手順
  （`./build.sh --notarize` と `NOTARY_KEY_PATH` env）が、実際の
  `build.sh` の実装（`./build.sh release <key-id> <issuer-id>`、
  `.p8` は固定パス `~/.appstoreconnect/private_keys/AuthKey_<id>.p8` 参照、
  `NOTARY_KEY_PATH` は未使用）と食い違っている。ドキュメントか build.sh の
  どちらかを合わせる対応が別タスクとして必要（本タスクは build.sh 非改変が
  非対象指定のため未対応）。
- リバート済みの Add Custom App パネル表示バグ（値は更新されるが
  NSTextField が再描画されない。NSAlert 方式でも再現）は未解決のまま。
  必要なら `docs/KNOWN_ISSUES.md` への追記を別タスクで検討。
