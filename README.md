# DevForge

**DevForge** is an in-game developer toolkit for World of Warcraft addons.

It provides live inspection, debugging, and exploration tools directly inside the WoW client — aimed at addon authors, tinkerers, and anyone who wants deeper visibility into the game’s UI and API surface.

DevForge is designed to be **self-contained**, **dependency-light**, and usable across **Retail and Classic** clients.

---

## Features

### Core Developer Tools
- **Live Frame & Object Inspector**
  - Hover and select frames
  - Inspect properties, scripts, and hierarchy
- **Event Monitor**
  - Subscribe to events and observe payloads in real time
- **Lua Console**
  - Execute Lua snippets safely
  - Inspect globals, tables, and runtime state
- **Table Viewer**
  - Explore nested tables interactively
- **Error & Stack Trace Viewer**
  - Capture and inspect runtime errors
- **CVar Browser**
  - View and modify CVars with visibility into defaults and current values
- **Macro & Snippet Editors**
  - Author, test, and iterate on code directly in-game

### Advanced Tooling
- **API Browser**
  - Explore available WoW APIs and namespaces
  - Adapts based on client capabilities
- **Texture & Atlas Browser**
  - Browse textures, atlases, and runtime-loaded assets
- **Performance Utilities**
  - Lightweight profiling helpers and diagnostics

### WeakAura → Addon Bridge (Retail Only)
- **WA Importer**
  - Converts WeakAura configurations into addon-backed logic
  - Intended as a bridge as Retail addon restrictions evolve
  - *Not required or loaded on Classic clients*

---

## Supported Clients

| Client | Status |
|------|------|
| Retail (Mainline) | ✅ Full support |
| Classic (current line) | 🧪 In progress (targeting parity) |
| Classic Era | 🧭 Planned |

DevForge uses client detection and feature gating to ensure safe behavior across versions.

---

## Installation

1. Download the latest release
2. Extract into: World of Warcraft/<client>/Interface/AddOns/DevForge

3. Restart WoW or run `/reload`

DevForge does not require external addon dependencies.

---

## Usage

DevForge provides a unified in-game UI.  
Open it via:
- Slash command (shown in-game)
- Addon Compartment button (Retail only)

Each tool is organized into modules accessible via tabs.

> ⚠️ Some tools allow live code execution. These are intended for development and debugging use only.

---

## Philosophy

DevForge aims to:
- Minimize external dependencies
- Favor transparency over automation
- Adapt to changing WoW addon constraints
- Support both experimentation and serious addon development

It is **not** intended to automate gameplay or bypass secure restrictions.

---

## Development & Architecture

High-level architecture and module layout are documented in: ARCHITECTURE.md



Key design points:
- Modular, capability-gated features
- Centralized compatibility and API abstraction
- Safe degradation on unsupported clients

---

## License

CC0 License

---

## Contributing

Issues and pull requests are welcome once the project is publicly open.

If you’re interested in extending DevForge or helping with Classic parity, feel free to reach out.

---

