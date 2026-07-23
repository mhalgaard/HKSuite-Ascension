# HKSuite — Project Conventions

Addon suite for **Project Ascension** (WoW 3.3.5a / WotLK client, Interface 30300).
Lua + XML-free UI, using the retail-of-the-era WoW API.

## Architecture
- `Core.lua` — suite framework: module registry, SavedVariables (`HKSuiteDB`),
  defaults merging, per-module enable flags, shared UI helpers (`ns.CreateCheck`),
  `/hk` slash command.
- `Overview.lua` — the top-level **HKSuite** options page. Auto-lists every
  registered module with an enable/disable checkbox.
- `Modules/<Name>.lua` — one file per utility. Contains the behavior AND its own
  settings sub-page.

## Rule: every new module MUST be added to the Overview page
The Overview is a **quick enable/disable area for all modules**. This happens
automatically *as long as the module follows the registration convention* — the
Overview iterates `ns.modules` and renders a toggle for anything with a `key`
and `title`.

When creating a new module:

1. Register it with `key`, `title`, and `desc`:
   ```lua
   local ADDON, ns = ...
   local M = ns.RegisterModule({
       key   = "mymodule",                 -- unique; also its SavedVariables sub-table
       title = "My Module",                -- shown on the Overview
       desc  = "One-line description.",    -- Overview tooltip
   })
   ```
2. Declare defaults under that key: `ns.defaults.mymodule = { enabled_thing = true }`.
3. In `M:OnInit()`, read `ns.config.mymodule`, register events, and **guard all
   behavior** behind the module toggle so the Overview switch actually works:
   ```lua
   frame:SetScript("OnEvent", function(_, event, ...)
       if ns.IsModuleEnabled("mymodule") then handlers[event](...) end
   end)
   ```
4. Give it a settings sub-page nested under the Overview:
   ```lua
   local panel = CreateFrame("Frame")
   panel.name = "My Module"
   panel.parent = "HKSuite"        -- nests it under the Overview page
   -- ...build with ns.CreateCheck(...)
   InterfaceOptions_AddCategory(panel)
   ```
5. Add the file to `HKSuite.toc` (after `Overview.lua`).

See `Modules/QuestAutomation.lua` as the reference implementation.

## Rule: prototype new modules in Scratch.lua (avoid restarts)
The client only scans for addons/files at launch, so **adding a new file to the
`.toc` requires a restart** (or at least a relog); `/reload` alone won't reliably
load a brand-new file. Editing an already-loaded file, however, only needs
`/reload`.

To keep iteration fast, `Modules/Scratch.lua` is permanently listed in the toc.
**Develop new modules there first** — since the file is always loaded, changes
are picked up with just `/reload`. When the module is finished:

1. Move the code to its own `Modules/<Name>.lua`.
2. Add that file to `HKSuite.toc`.
3. Reset `Scratch.lua` back to its empty template.
4. This promotion needs one restart — batch it with other new modules.

Default expectation when telling the user how to test:
- Edited an existing file (incl. Scratch.lua) → `/reload`.
- Added a new file to the toc / new addon → restart (or relog, then restart).

## Rule: deploy to the game after every change
Whenever addon files change, copy the whole `HKSuite` folder into the live client
AddOns directory so it can be tested in-game:

```
C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns\HKSuite
```

PowerShell:
```powershell
robocopy "c:\Projects\HKSuite" "C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns\HKSuite" /MIR /NFL /NDL /NJH /NJS
```
(`/MIR` mirrors the folder, so deletions/renames are reflected too.)

After copying, the game must reload to pick up Lua changes: `/reload` in-game, or
log out to character select and back in. New/removed files require a full client
restart.

## Conventions
- UI text uses `ns.CreateCheck` for checkboxes so styling stays consistent.
- Colored addon-name prefix for chat output via `ns.Print`.
- Keep behavior modules self-contained: events + options panel in the one file.
