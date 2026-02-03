---
title: DevForge
---

# DevForge

**DevForge** is a developer toolkit addon for World of Warcraft.

It brings inspection, debugging, and exploration tools directly into the game client — designed for addon authors and technical users who want deeper visibility into WoW’s UI and API systems.

---

## What DevForge Does

DevForge provides tools to:

- Inspect live frames, objects, and tables
- Observe events and runtime behavior
- Execute Lua snippets safely
- Explore available APIs and assets
- Debug errors and performance issues

All from inside the game.

---

## Core Tools

### 🔧 Interactive Lua Console

![DevForge Console]({{ site.baseurl }}/assets/images/editor.png)

Write and execute Lua snippets directly in-game with a persistent scratchpad and saved snippets.

- Execute exploratory code safely
- Inspect tables and runtime state
- Maintain reusable snippets
- Clearly marked tainted execution context

---

### 🔍 Live Frame Inspector

![DevForge Frame Inspector]({{ site.baseurl }}/assets/images/inspector.png)

Inspect live UI frames in real time.

- Traverse frame hierarchies
- View geometry, strata, anchors, and visibility
- Inspect registered events and scripts
- Jump directly to Blizzard Frame Stack output
- Generate helper code from selected frames

---

## Why DevForge Exists

As World of Warcraft’s addon environment continues to evolve — especially with increasing restrictions in Retail — developers need better visibility and safer tooling.

DevForge focuses on:
- Transparency over automation
- Capability-based features
- Compatibility across Retail and Classic clients

It also includes optional tooling designed to help bridge existing workflows as the addon ecosystem changes.

---

## Feature Overview

DevForge is composed of a set of focused tools that can be used independently or together during addon development and debugging.

Each feature is documented individually with screenshots and usage notes.

### Core Tooling
- **[Interactive Lua Console](features/console.md)**  
  Execute Lua snippets, inspect runtime state, and experiment safely in-game.

- **[Code Editor & Project Tools](features/editor.md)**  
  Manage snippets and templates, scaffold addon projects, and import WeakAura logic (Retail).

- **[Frame Inspector](features/inspector.md)**  
  Inspect live UI frames, geometry, anchors, events, and scripts in real time.

- **[API Browser](features/api-browser.md)**  
  Explore available APIs and namespaces based on the active client environment.

### Runtime Observation
- **[Event Monitor](features/event-monitor.md)**  
  Observe live events, inspect payloads, and filter noisy event streams.

- **[Table Viewer](features/tables.md)**  
  Explore Lua tables, SavedVariables, globals, and runtime state interactively.

- **[Error Review Panel](features/errors.md)**  
  Review captured Lua errors with stack traces and local variable inspection.

### System & Diagnostics
- **[CVar Viewer & Maintenance](features/cvars.md)**  
  Inspect and manage client configuration variables safely.

- **[Macro Editor & Validation](features/macros.md)**  
  View, edit, validate, and test account and character macros.

- **[Performance Monitor](features/performance.md)**  
  Inspect addon memory usage and optional CPU sampling over time.

---

## Client Support

- **Retail:** Fully supported
- **Classic (current line):** Actively targeting parity
- **Classic Era:** Planned

Features automatically adapt based on client capabilities and available APIs.

---

## Installation

Download the addon and extract it into your WoW AddOns folder:
World of Warcraft/<client>/Interface/AddOns/DevForge


Restart the game or reload the UI.

---

## Project Status

DevForge is under active development and approaching its initial public release.

Documentation, contribution guidelines, and additional tooling details will expand over time.

---

## Links

- GitHub Repository
- Issue Tracker
- Architecture Overview

---

> ⚠️ DevForge includes tools that allow live Lua execution.  
> It is intended for development and debugging use only and does not automate gameplay or bypass secure systems.

