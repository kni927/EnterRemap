# EnterRemap

English | [日本語](README-ja.md)

A lightweight macOS utility that changes the **Return** key to **Send** in supported native macOS applications.

This project is intended for **native macOS applications only**. If you use ChatGPT in a web browser, a browser extension is a more appropriate solution.

## Features

* Remaps the main **Return** key (`kVK_Return`) for supported macOS applications
* Leaves the keypad **Enter** key (`kVK_ANSI_KeypadEnter`) untouched
* Compatible with both Apple Japanese Input and Google Japanese Input
* Works with applications such as Discord that normally do not distinguish Return and Enter
* Lightweight native Swift menu bar application

## How It Works

EnterRemap intentionally remaps **only** the main keyboard **Return** key.

| Key                                   | Behavior                                                 |
| ------------------------------------- | -------------------------------------------------------- |
| Return (`kVK_Return`)                 | Remapped                                                 |
| Keypad Enter (`kVK_ANSI_KeypadEnter`) | Unchanged (application default behavior, typically Send) |

Keeping the keypad Enter key unchanged allows applications to continue using their original behavior while changing only the main Return key.

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

## Usage

EnterRemap runs as a small icon in the menu bar (no Dock icon). Click it
for:

* **Target Apps** — a checklist of which apps the remap applies to
  (Claude, ChatGPT, ChatGPT Classic, and Gemini are on by default;
  **Discord is off by default** — enable it here if you want the remap
  in Discord). "Add Custom App..." lets you add any other app by its
  bundle identifier.
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
