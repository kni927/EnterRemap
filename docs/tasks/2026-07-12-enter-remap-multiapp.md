# TASK: マルチアプリ対応 Enter/Cmd+Enter リマップツール

## 背景
CGEventTap + eventSourceStateID判定によるIME安全な
Enter→改行 / Cmd+Enter→送信 変換ツールを、
Claude単体からマルチアプリ対応にリファクタする。

## 対象アプリ（bundle ID許可リスト）
- Claude: com.anthropic.claudefordesktop
- ChatGPT (新統合版, Codex統合後): com.openai.codex
- ChatGPT Classic (旧版、残存している場合): com.openai.chat
- Gemini: com.google.GeminiMacOS

## 要件
1. 許可リストを Set<String> で管理し、frontmost_application判定に使う
2. 既存のeventSourceStateID判定（IME確定Enterを誤変換しない）ロジックは変更しない
3. アクセシビリティ権限、ログイン項目登録は既存実装を流用
4. 将来アプリ追加が容易なよう、bundle ID配列を定数化し1箇所で管理

## 非対象
- Web版（Chrome等ブラウザ）は対象外。既存のChrome拡張機能（Chat AI Ctrl+Enter Sender等）で
  対応済みのため、本ツールはネイティブMacアプリのみを扱う
- Gemini/ChatGPT側の常駐プロセス（GeminiAppLauncher, GoogleUpdater等）には関与しない
- PWA版Geminiには対応しない（ネイティブアプリのみ）

## 参考実装
https://qiita.com/nate3870/items/51b196de9a07717d3952

## Repo
新規リポジトリとして独立管理（kni927/EnterRemap 想定）。
cooViewer/FrameSheetと同様、プロジェクトごとに別repoの方針を踏襲。