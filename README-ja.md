# EnterRemap

[English](README.md) | 日本語

**EnterRemap** は、対応する **macOSネイティブアプリ**でメインキーボードの **Returnキー** の動作を変更する軽量なメニューバーユーティリティです。

本ツールは **macOSネイティブアプリ専用**です。ブラウザ版 ChatGPT などの Web アプリは対象としていません。

---

## 特徴

* メインキーボードの **Returnキー (`kVK_Return`)** をリマップ
* **テンキーの Enterキー (`kVK_ANSI_KeypadEnter`)** は変更しません
* Apple日本語入力・Google日本語入力の両方に対応
* Discord など、ReturnキーとEnterキーを区別しないアプリでも利用可能
* 軽量な Swift 製メニューバーアプリ

---

## 動作について

EnterRemap がリマップするのは、**メインキーボードの Returnキー (`kVK_Return`) のみ**です。

| キー                                  | 動作                         |
| ----------------------------------- | -------------------------- |
| Return (`kVK_Return`)               | リマップされます                   |
| テンキー Enter (`kVK_ANSI_KeypadEnter`) | 変更されません（アプリ本来の動作のまま。通常は送信） |

テンキーの Enterキーは意図的に変更していません。

そのため、アプリ側の標準動作との互換性を維持したまま、メインキーボードの Returnキーだけを変更できます。

---

## 対応範囲

本ツールは **macOSネイティブアプリ**を対象としています。

例：

* ChatGPT Desktop
* Claude Desktop
* Discord
* その他対応するネイティブアプリ

Chrome や Safari 上で動作する **Web版 ChatGPT** などは対象外です。

ブラウザ版 ChatGPT を利用する場合は、以下のような拡張機能の利用をおすすめします。

* **ChatGPT Ctrl+Enter Sender**

---

## インストール

1. 最新版をダウンロード
2. **EnterRemap.app** を **アプリケーション**フォルダへ移動
3. 起動
4. アクセシビリティ権限を許可

---

## 使い方

EnterRemapはメニューバーの小さいアイコンとして常駐します(Dockアイコンなし)。
クリックすると:

* **Target Apps** — リマップを適用するアプリのチェックリスト
  (Claude / ChatGPT / ChatGPT Classic / Geminiは初期状態ON。
  **Discordは初期状態OFF** — Discordでもリマップしたい場合はここで有効化する)。
  「Add Custom App...」から任意のアプリをbundle IDで追加できる
* **Pause / Resume** — 終了せずに一時的にリマップを無効化
* **Open Login Items Settings...** — システム設定のログイン項目ページを
  直接開く。ここでEnterRemapを追加すればログイン時に自動起動する
* **Quit**

アイコン自体でも状態がひと目でわかる: 稼働中はモノクロ、一時停止中は黄色、
キーボードフックの復帰に失敗し再起動が必要な場合は赤で表示される。

---

## 開発のきっかけ

本プロジェクトは、Claude Desktop で **「Enterで改行、Command+Enterで送信」** を実現する以下の記事に着想を得て開発しました。

https://qiita.com/nate3870/items/51b196de9a07717d3952

その後、

* Google日本語入力への対応
* Discordなど追加アプリへの対応
* 軽量な常駐ユーティリティ化

などを行い、より汎用的なツールとして公開しています。

---

## ライセンス

MIT License
