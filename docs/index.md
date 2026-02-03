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

