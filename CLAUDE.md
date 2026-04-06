# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**freeinventory** is an addon for [Ashita v4](https://ashitaxi.com/), a plugin framework for Final Fantasy XI. It scans all inventory bags for duplicate items across bags and partial stacks within bags, helping players free up inventory slots.

## Ashita Addon Framework

This is a single-file Lua addon (`freeinventory.lua`) that runs inside the Ashita v4 runtime. Key framework APIs used:

- **`AshitaCore:GetMemoryManager():GetInventory()`** — reads container slots, item counts, max slots
- **`AshitaCore:GetResourceManager():GetItemById(id)`** — resolves item IDs to resource objects (name, stack size)
- **`ashita.events.register(event, name, callback)`** — hooks into `command`, `load`, `unload` events
- **`require('common')` / `require('chat')`** — Ashita standard libraries for table extensions (`T{}`, `:args()`, `:any()`) and chat formatting (`chat.header`, `chat.message`, `chat.success`, `chat.error`)

The addon metadata block (`addon.name`, `addon.author`, `addon.version`, `addon.desc`, `addon.commands`) is required by Ashita's addon loader.

## Architecture

The addon has three layers in a single file:

1. **Container definitions** — static table mapping bag IDs (0–16) to display names (Inventory, Safe, Wardrobe, etc.)
2. **Scan & analysis** — `scan_inventory()` reads all items from all bags; `find_dupes()` groups by item ID and detects cross-bag duplicates and same-bag partial stacks
3. **Commands & output** — registered via `/freeinv` command: default scans, `export` writes CSV, `help` prints usage

## Commands (in-game)

- `/freeinv` — scan and report duplicates/partial stacks
- `/freeinv export` — export full inventory to `inventory.csv` in the addon directory
- `/freeinv help` — show usage

## Development Notes

- No build step — Lua is interpreted by Ashita at runtime
- No test framework — testing is done in-game by loading the addon (`/addon load freeinventory`)
- `inventory.csv` in the repo is sample/reference data, not source code
- Item names use a language-index fallback (indices 0→2→1→3) preferring ASCII/English names
- Inventory slot 0 in bag 0 is skipped (it holds gil)
