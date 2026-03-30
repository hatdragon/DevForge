---
title: API Browser
---

# API Browser

The API Browser provides visibility into the functions, namespaces, and APIs available in the current WoW client.

It is designed to answer a simple but critical question:

**“What APIs exist here, right now?”**

---

## Overview

World of Warcraft exposes a large and evolving API surface that differs between clients, patches, and environments.

The API Browser allows you to:
- Explore available global APIs
- Browse `C_*` namespaces
- Inspect function signatures
- Verify availability at runtime

---

## Screenshot

![DevForge API Browser]({{ site.baseurl }}/assets/images/api-browser.png)

---

## Capabilities

### Namespace Exploration
- Browse top-level globals
- Expand tables and namespaces
- Quickly locate functions

### Function Inspection
- View parameters and return values
- See documentation metadata when available
- Insert function calls directly into the console or editor

### Client Awareness
The API Browser reflects **what the client actually provides**, not assumptions.

This is especially important when working across:
- Retail
- Classic
- Patch boundaries

---

## When to Use the API Browser

Use the API Browser when:
- Discovering unfamiliar APIs
- Verifying function availability
- Writing cross-client compatible code
- Exploring new patch changes
