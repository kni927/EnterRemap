# TASK: 異常終了通知の追加とREADME整備（Phase 4）

## 背景
rebuild後の再起動忘れなど、EnterRemapが意図せず終了していることに
気づく手段が `pgrep -l EnterRemap` での手動確認しかなく、わかりにくい。
launchd + KeepAliveによる自動再起動も検討したが、`killall`での意図的な
終了時にも復活してしまう副作用があるため見送り、通知による対症療法を採用する。

## 要件
1. UserNotifications framework で、以下のタイミングでmacOS通知を1回出す:
   - CGEventTapが `tapDisabledByTimeout` 等で無効化され、既存の
     自動再有効化ロジックでも復帰できなかった場合
   - プロセス終了シグナル（SIGTERM等）を捕捉できる範囲で、
     意図しない終了と判別できる場合（`killall`による意図的終了と
     区別する必要はない・区別できなくてもよい。「止まったことに
     気づける」ことが目的で、原因の切り分けは求めない）
2. 通知権限（UNUserNotificationCenter authorization）の要求は
   初回起動時に行う。README に許可が必要な旨を明記する
3. 既存のIME判定・composing state ロジックには触れない

## README整備（合わせて対応）
1. 状態確認・終了コマンドを明記する:
   ```bash
   pgrep -l EnterRemap   # 動作確認
   killall EnterRemap    # 終了（自動再起動はしない。ログイン項目に
                          # 登録されている場合は次回ログイン時に復帰）
   open /Applications/EnterRemap.app   # 再起動
   ```
2. 参考実装（Qiita記事）との差分を明記するセクションを追加する:
   - 元記事の実装は日本語IME対応を主眼としておらず、Apple標準の
     日本語入力（ライブ変換確定）のみ動作する前提だった
   - 本プロジェクトはGoogle日本語入力でも正しく動作させることを
     目的にPhase 2〜3で拡張した（TISゲート、AX/ウィンドウ検出、
     composing状態トラッキングの多層判定）
   - この差分を明記し、「なぜ同じような実装を再度行っているのか」が
     わかるようにする
3. README-ja.md / README.md（英語版）両方に反映する

## 非対象
- launchd化・自動再起動（KeepAlive）は見送り
- IME判定ロジックの変更
