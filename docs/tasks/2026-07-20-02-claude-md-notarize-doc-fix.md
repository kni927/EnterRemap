# TASK: CLAUDE.mdのnotarize手順を実際のbuild.shに合わせる

## 背景
housekeeping作業で判明した不一致。CLAUDE.mdのCommandsセクションには
`./build.sh --notarize` + `NOTARY_KEY_PATH` / `NOTARY_KEY_ID` /
`NOTARY_ISSUER_ID` 環境変数、と記載されているが、実際の build.sh は
`./build.sh release <key-id> <issuer-id>` という位置引数方式で、
`.p8` は固定パスを参照している。

## 要件
1. build.sh の実際のnotarize起動方法（サブコマンド/引数/固定パスの
   `.p8` の場所）を確認する
2. CLAUDE.mdのCommandsセクションを、確認した実際の仕様に合わせて修正する
   （ドキュメント側を実装に合わせる。build.shは変更しない）
3. `.p8` の固定パスがハードコードされている場合、そのパスも
   CLAUDE.mdに明記する（次回別マシンや別人が実行する際に迷わないように）

## 非対象
- build.sh のインターフェース変更（環境変数方式への変更等）
- Add Custom Appパネルの調査（別タスク）

## Implementation Result

**Status:** Completed

### Changes

- `CLAUDE.md` の Commands セクションの notarize 記述を実際の `build.sh`
  仕様に合わせて修正（build.sh は非改変）。
  - 誤: `./build.sh --notarize` + `NOTARY_KEY_PATH` env
  - 正: `./build.sh release <key-id> <issuer-id>`（または env
    `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID`）。Developer ID 署名 → App Store
    Connect API キー方式で notarize → staple → `build/EnterRemap-v<version>.zip`
    生成、と明記。
  - `.p8` の固定パス `~/.appstoreconnect/private_keys/AuthKey_<key-id>.p8`
    （key-id から内部導出、コマンドラインでは渡さない）を明記（要件3）。
- build.sh 実装の確認結果（要件1）:
  - サブコマンドは位置引数 `release`（`--notarize` は存在しない）
  - key-id / issuer-id は位置引数2/3、または同名 env で受ける
  - `NOTARY_KEY_PATH` という env は存在せず、パスは NOTARY_KEY_ID から導出
  - `xcrun notarytool submit --key <path> --key-id <id> --issuer <id> --wait`

### Verification

- Build: 未実施（CLAUDE.md のドキュメント修正のみ。コード非改変）。
- Automated verification: `grep -n "notarize\|NOTARY_KEY_PATH" CLAUDE.md` で
  旧記述（`--notarize` サブコマンド / `NOTARY_KEY_PATH`）が残っていないことを確認。
  build.sh の該当行（MODE=release 分岐、key path 導出、notarytool 呼び出し）を
  読み合わせ、記述内容と一致することを確認。
- Manual verification: 修正後 Commands セクションの目視確認。
- Not performed: 実際の notarize 実行（本タスクはドキュメント整合のみ）。

### Remaining Issues

- None。

### Follow-up Suggestions

- None（本タスク由来の新規事項なし）。既知の未解決事項として、リバート済みの
  Add Custom App パネル表示バグは別タスク管理のまま。
