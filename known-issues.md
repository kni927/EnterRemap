# Known Issues

## IME候補ウィンドウのマウスクリック挙動

変換候補リストが表示された状態で:

- 上部の入力文字列(合成中テキスト)をクリック → 選択状態が解除され、
  本来の(キーボード操作時と同じ)挙動に戻る
- 候補そのものをクリック → 選択状態がそのまま残る

いずれの場合も次の入力自体は問題なく行えるため実害はほぼない。
そもそも変換確定をマウスクリックで行うこと自体が稀な操作のため、
現状のまま許容する(2026-07-12、Phase 3実装時に確認)。

## 異常終了通知(UserNotifications)が開発環境で検証できなかった

Phase 4でUserNotifications frameworkによる異常終了通知を実装したが、
開発マシン(macOS 26.5.1)では以下の理由で通知の到達を確認できなかった:

- `UNUserNotificationCenter.requestAuthorization` が
  `UNErrorDomain Code=1 "Notifications are not allowed for this application"`
  で失敗する
- システム設定 > 通知 に EnterRemap 自体が一覧に表示されない
  (許可/拒否以前に登録すらされていない)
- `spctl -a -vv /Applications/EnterRemap.app` は
  `rejected / source=Unnotarized Developer ID` — Developer ID証明書
  (`Developer ID Application: Kuniharu Nishimura`)で署名しても
  Gatekeeperに拒否される。ad-hoc署名(現在のbuild.shのデフォルト)でも
  同様に通知権限が下りない

このmacOSバージョンでは、UNUserNotificationCenterによる通知権限の
要求自体に**公証(notarization)**が必要になっている可能性が高い。
公証にはApple Developer AccountでのnotarytoolによるApple提出+
ステープルが必要で、アーキテクチャ上の判断(配布方針の変更)を伴うため、
実施するかどうかはユーザー側で判断すること。

実装自体(許可要求・通知発火・シグナルハンドラ)は標準的な書き方で、
公証済みの環境であれば動作する見込みだが、この開発環境では
実機確認が取れていない状態でPhase 4を完了とした。
