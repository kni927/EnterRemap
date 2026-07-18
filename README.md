# EnterRemap

English | [日本語](README-ja.md)

A lightweight macOS utility that changes the **Return** key to **Send** in supported native macOS applications.

This project is intended for **native macOS applications only**. If you use ChatGPT in a web browser, a browser extension is a more appropriate solution.

## Features

* Remaps the main **Return** key (`kVK_Return`) for supported macOS applications
* The keypad **Enter** key (`kVK_ANSI_KeypadEnter`) is left untouched by
  default, but can be included in the remap from the menu bar
* Compatible with both Apple Japanese Input and Google Japanese Input
* Works with applications such as Discord that normally do not distinguish Return and Enter
* Lightweight native Swift menu bar application

## How It Works

By default EnterRemap remaps only the main keyboard **Return** key.

| Key                                   | Behavior                                                              |
| ------------------------------------- | ---------------------------------------------------------------------|
| Return (`kVK_Return`)                 | Remapped                                                              |
| Keypad Enter (`kVK_ANSI_KeypadEnter`) | Unchanged by default (application default, typically Send) — optional|

Turning on **Remap Keypad Enter** in the menu bar routes the keypad
Enter key through the exact same logic as Return (including IME and
text-field detection), so it behaves identically instead of falling
back to each app's own default.

## Scope

This application targets **native macOS applications**.

Examples include:

* ChatGPT Desktop
* Claude Desktop
* Discord
* Other supported native macOS applications

Web applications running in browsers (Chrome, Safari, Edge, etc.) are **not** the target of this project.

For ChatGPT on the web, using a browser extension is recommended instead, for example:

* **ChatGPT Ctrl+Enter Sender**

## Installation

1. Download the latest release.
2. Move **EnterRemap.app** to the Applications folder.
3. Launch the application.
4. Grant Accessibility permission when prompted.

> **Upgrading from v1.5.2 or earlier**: the app's bundle identifier
> changed (`com.local.enter-remap` → `com.kni.EnterRemap`). macOS treats
> this as a different app, so after upgrading you'll need to: re-grant
> Accessibility permission, re-add EnterRemap to Login Items, and
> reconfigure Target Apps (settings don't carry over from the old
> identifier — they reset to the defaults on first launch).

## Usage

EnterRemap runs as a small icon in the menu bar (no Dock icon). Click it
for:

* **Target Apps** — a checklist of which apps the remap applies to
  (Claude, ChatGPT, ChatGPT Classic, and Gemini are on by default;
  **Discord is off by default** — enable it here if you want the remap
  in Discord). "Add Custom App..." opens a small window where you can
  type a bundle identifier or just drag the app's `.app` file onto it.
* **Remap Keypad Enter** — off by default; see "How It Works" above.
* **Pause / Resume** — temporarily disable the remap everywhere without
  quitting.
* **Open Login Items Settings...** — jumps straight to System Settings'
  Login Items page, where you can add EnterRemap so it starts
  automatically at login.
* **Quit**.

The icon itself shows status at a glance: gray-scale when running,
yellow when paused, red if the keyboard hook failed to recover and the
app needs a restart.

## Background

This project was inspired by the following article describing how to use **Enter for newline and Command+Enter for Send** in the Claude desktop application.

* https://qiita.com/nate3870/items/51b196de9a07717d3952

While that article focuses on Claude Desktop, EnterRemap generalizes the idea into a lightweight background utility that also supports Google Japanese Input and additional native macOS applications such as Discord.

## License

MIT License.
