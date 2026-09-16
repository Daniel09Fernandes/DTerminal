# DTerminal 🦖

<img width="200" height="200" alt="image" src="https://github.com/user-attachments/assets/7237022f-4f1c-41f6-aa02-c03e536668b8" />


**A full-featured terminal docked inside the Delphi IDE.**

DTerminal is an open-source, design-time Delphi IDE plugin that embeds a real terminal directly into RAD Studio / Delphi. It runs on **Delphi 10.3 (Rio) and later**. It gives you a native **Command Prompt (CMD)**, **PowerShell**, and **WSL (Linux)** shell without leaving your development environment — with color output, cursor handling, scrolling, copy/paste and command interruption.

Shells see your current user PATH, so **AI agent CLIs** such as Cursor (`agent` / `cursor-agent`), OpenCode and similar tools work from the project folder, just like in a normal terminal.

It is built on top of the Windows **ConPTY** API, so it renders real VT/ANSI output through a custom screen buffer and VT parser.
---

## Usability

<img width="1623" height="817" alt="dinosterminal" src="https://github.com/user-attachments/assets/ce26ea45-9667-4665-96da-b4f1f40954a9" />


---

## ✨ Features

- **Delphi 10.3+** — design-time package for RAD Studio / Delphi **10.3 (Rio)** and later. Compile and install it in the same IDE version you will use.
- **AI agent CLIs** — Cursor (`agent` / `cursor-agent`), OpenCode and other user-installed agent CLIs are on the shell PATH and start in the active project folder.
- **Dockable inside the IDE** — registers as a dockable form via the Open Tools API, persists across Design and Debug layouts.
- **Multi-terminal tabs** — open as many CMD, PowerShell or WSL shells as you want, each in its own tab.
- **True VT rendering** — SGR colors (16/256/RGB), bold/italic/underline/inverse, cursor positioning, scroll regions, alternative screen buffer and OSC window titles.
- **Scrollback** — scroll back through output history (mouse wheel / scrollbar).
- **Copy & paste** — select with the mouse and copy (`Ctrl+C` / context menu), paste with `Ctrl+V` or the context menu.
- **Interrupt long-running commands** — press `Ctrl+Break` (or `Ctrl+Pause`) to send an interrupt (`#3`, equivalent to `Ctrl+C`) to the foreground process. Great for `ping -t`, `tail -f`, custom servers, etc.
- **History** — arrow-up/down navigation on the input line (CMD/PowerShell/WSL shells provide their own history as well).
- **Window titles** — OSC `0;title` sequences update the tab caption.
- **Solid engine** — UTF-8 aware reader, partial multibyte sequence handling, unicode-tolerant pipes, job objects to guarantee children are killed on close.
- **User PATH** — shells use the current user/machine PATH from the registry (expanded, including tools under `%LOCALAPPDATA%`), not the stale IDE process PATH.
- **Project directory** — new terminals open in the active Delphi project folder.

---

## AI agent CLIs

DTerminal is compatible with AI agent command-line tools installed for your Windows user — for example **Cursor** (`agent` / `cursor-agent`), **OpenCode**, and other CLIs that live on the user PATH (often under `%LOCALAPPDATA%`).

- The shell does **not** inherit the stale PATH from the Delphi IDE process. It rebuilds PATH from the current user and machine environment, so tools you installed after opening the IDE still resolve.
- A new tab starts in the **active Delphi project folder**, so the agent works on the code you have open.
- ConPTY plus the VT renderer support interactive CLIs (colors, cursor, TUI). If ConPTY is unavailable, the pipe fallback still runs basic commands; full-screen TUIs may degrade.
- DTerminal does **not** install the agent. Install the CLI yourself and make sure it is on the Windows user PATH.

---

## 🛠️ Requirements

- **Delphi 10.3 (Rio) or later** (RAD Studio) with VCL and **design-time package** support. Compile and install the package in the **same IDE version** you will use.
- **Windows 10** (build **17763** / 1809 or later) / Windows 11 — ConPTY is used when available. On older Windows, or if ConPTY fails to start, the terminal falls back to redirected pipes (basic CMD/PowerShell still work; full-screen VT apps degrade).
- **WSL** — only if you want to use the Linux/WSL terminal (optional).
- **AI agent CLIs** (optional) — install Cursor, OpenCode or another agent CLI on your user PATH if you want to run them from the docked terminal.

---

## 📦 Installation

1. Clone the repository and open **`DinosTerminal.dproj`** in Delphi.
2. In the **Project Manager**, right-click the project and run, in this exact order:
   - 🧼 **Clean**
   - 🔨 **Build**
   - ⚡ **Install**
3. After installation, a new menu **DinosTools** appears in the IDE main menu.
4. Click `DinosTools -> DinosTerminal` to open the terminal.

---

## 🚀 Usage

### Opening a shell
- The first tab opens **CMD** automatically, in the folder of the active Delphi project (falls back to the IDE working directory if no project is open).
- Right-click the tab bar → **New Terminal** → choose `CMD`, `WSL` or `PowerShell`.
- Right-click a tab to **rename** or **remove** it (the default tab cannot be removed/renamed).

### Running an AI agent CLI
From the prompt in the project folder, call the CLI you already installed, for example:

```text
agent
cursor-agent
opencode
```

The command resolves from your user PATH. The working directory is the active Delphi project, so the agent starts in the same tree you are editing.

### Keyboard shortcuts
| Shortcut | Action |
| --- | --- |
| `Ctrl+Break` | Interrupt the running foreground command |
| Arrow up / down | Shell history / previous commands |
| Tab | Auto-completion (handled by the shell) |

### Copy / Paste
- **Copy:** select text with the mouse, then right-click → *Copy*.
- **Paste:** right-click → *Paste*.

---

## 🧩 Architecture

The package is split into small, focused units under the `Dinos.Terminal.*` and `WinAPI.*` namespaces:

| Unit | Responsibility |
| --- | --- |
| `uMain.pas` | `TManangerTerminal` — dockable form (`INTACustomDockableForm`) managing tabs and shell processes |
| `uRegister.pas` | OTA wizard that adds the `DinosTools` menu entry |
| `WinAPI.ConPty.pas` | Dynamic loading of the ConPTY API (`CreatePseudoConsole`, `ResizePseudoConsole`, ...) with Windows 1809+ build check |
| `Dinos.Terminal.Pty.pas` | `TConPty` — pipes + pseudo-console + job object (`KILL_ON_JOB_CLOSE`) + `CreateProcess` wiring |
| `Dinos.Terminal.ProcessEnv.pas` | Fresh user/machine PATH (registry, expanded) packed into a Unicode environment block for `CreateProcess` |
| `Dinos.Terminal.ConPtyReader.pas` | Background thread that reads output and decodes UTF-8, keeping partial sequences intact |
| `Dinos.Terminal.ConPtyShell.pas` | `ITerminalProcess` implementation — lifecycle, resize, interrupt, exit events |
| `Dinos.Terminal.CmdShell.pas` | Pipe-based `ITerminalProcess` fallback when ConPTY is missing or fails to start |
| `Dinos.Terminal.ScreenBuffer.pas` | Cell-based screen buffer: colors, styles, scrollback, scroll regions, alt-screen |
| `Dinos.Terminal.VTParser.pas` | CSI / OSC / SGR / control-character parser driving the screen buffer |
| `Dinos.Terminal.TerminalView.pas` | Painting control: cell runs, xterm palette, cursor, selection, scrolling |
| `Dinos.Terminal.KeyInput.pas` | Key strokes → VT sequences (arrows, Home/End, F1-F12, Ctrl+C/V/Z) |
| `Dinos.Terminal.Frame.pas` | Ties everything together per tab and implements the local input line |
| `Dinos.Terminal.Interrupt.pas` | Low-level keyboard hook for `Ctrl+Break` interrupt handling |
| `Dinos.Terminal.Debug.pas` | Structured logging and global exception handler (writes to `%TEMP%\DinosTerminal.log`) |

```
 TTerminalView <──> TScreenBuffer <──> TVTParser <── TConPtyReader (thread) <── ConPTY
    │   ▲                                          │
    │   └──── keyboard ─► TKeyToVT ────► TConPtyShell ─► TConPty ─► CreateProcess
    └──── selection / scroll / paint                      (pipes + job + pty)
```

> **Debugging:** a verbose log is written to `%TEMP%\DinosTerminal.log`. Check it when reporting bugs.


---

## 🧑‍💻 Contributing

Contributions are welcome!

1. Fork the repository.
2. Create a feature branch.
3. Make sure the package **Clean → Build → Install** with **no warnings related to your change**.
4. Open a Pull Request describing the change and how to test it.

Bug reports and feature requests go to the [issue tracker](https://github.com/Daniel09Fernandes/DTerminal/issues).

---

## 📄 License

MIT License. See [LICENSE](LICENSE).
