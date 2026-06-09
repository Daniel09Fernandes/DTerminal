# DTerminal 🦖

**Alpha Version**

**DTerminal** is a command-line terminal integrated directly into the Delphi IDE. It allows you to execute commands and automate tasks without leaving your development environment, offering full compatibility with **WSL (Linux)**, **CMD**, and **PowerShell**.

<img width="110" height="132" alt="image" src="https://github.com/user-attachments/assets/eac222ed-648c-4944-98a8-8faa67ebe93b" />


---

## 🚀 Features

* **Native Integration:** Works as a dockable window (*Dockable Form*) inside the Delphi IDE.
* **Multi-Terminal:** Native support for WSL, Command Prompt (CMD), and PowerShell.
* **Layout Persistence:** Stays pinned to your environment in both design and debug modes.

---

## 🛠️ How to Install and Activate

To install the plugin in your IDE, follow the steps below:

1. Open the package project `DinosTerminal.dproj` in your Delphi.
2. In the **Project Manager**, right-click the project and execute the actions in this exact order:
   * 🧼 **Clean**
   * 🔨 **Build**
   * ⚡ **Install**
3. After installation, a new menu named **DinosTools** will appear in the top bar of the IDE.
4. Click `DinosTools -> DinosTerminal` to open the terminal window.

---

## 📐 Recommended Layout Setup (Docking)

Since Delphi manages layouts separately for coding and debugging, follow this suggestion so your terminal never disappears from the screen:

1. **Default Layout (Design):**
   * Open the terminal from the menu.
   * Drag and **dock** the window to your preferred location (e.g., next to the bottom Messages tab).
   * Go to the IDE's top menu: `View -> Desktops -> Save Desktop...`
   * Select or type **Default Layout** and save.

2. **Debugging Layout (Debug):**
   * Start debugging any project (**F9**). The IDE layout will change.
   * If the terminal disappears, go to `DinosTools -> DinosTerminal` again (it will open instantly).
   * Position and dock the terminal where you want it to stay while debugging.
   * Go to the IDE's top menu: `View -> Desktops -> Save Desktop...`
   * Select or type **Debug Layout** and save.

All set! Now the terminal will automatically move and adapt whenever you switch between coding and debugging.

---

## 📸 Demonstration

<img width="357" height="206" alt="image" src="https://github.com/user-attachments/assets/4813b859-98c5-42ad-9a5b-5a3af2c436e8" />



<img width="1358" height="722" alt="TerminalDelphi" src="https://github.com/user-attachments/assets/7ffc1a57-4288-44b3-b424-59f89af83c57" />


---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.
