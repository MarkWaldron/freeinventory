# freeinventory

An [Ashita v4](https://ashitaxi.com/) addon for Final Fantasy XI that scans every inventory bag and reports ways to free up slots: partial stacks that can be merged, and stackable items duplicated across bags that can be consolidated.

## What it does

`freeinventory` walks all 17 containers (Inventory, Safe, Storage, Locker, Satchel, Sack, Case, and Wardrobes 1–8), groups items by ID, and surfaces three categories:

1. **Quick wins — partial stacks in the same bag.** If you have `Crystal x6 + Crystal x3` in Satchel, that's one slot you can merge.
2. **Cross-bag stackable consolidation.** Same item ID present in multiple bags, with enough room to combine into fewer stacks.
3. **FYI — unstackable gear duplicates.** Equipment dupes spread across bags. Reported for awareness, since they can't actually be stacked.

A summary line at the bottom totals slots freeable from each category.

## Installation

1. Drop the `freeinventory/` folder into `<Ashita>/addons/`.
2. In-game: `/addon load freeinventory`.

## Commands

| Command | Description |
| --- | --- |
| `/freeinv` | Scan and report duplicates and partial stacks. |
| `/freeinv export` | Write the full inventory to `inventory.csv` in the addon directory. |
| `/freeinv help` | Show usage. |

## Notes

- Slot 0 of the Inventory bag is skipped (gil).
- Item names are read with a language-index fallback (0 → 2 → 1 → 3) preferring readable ASCII/English.
- No build step — Lua is interpreted by Ashita at runtime. Test by reloading the addon in-game.
