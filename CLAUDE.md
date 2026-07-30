# HKSuite — Project Conventions

Addon suite for **Project Ascension** (WoW 3.3.5a / WotLK client, Interface 30300).
Lua + XML-free UI, using the retail-of-the-era WoW API.

## Architecture
- `Core.lua` — suite framework: module registry, SavedVariables (`HKSuiteDB`),
  defaults merging, per-module enable flags, `/hk` slash command.
- `SettingsUI.lua` — HKSuite's standalone settings window plus `ns.UI`, the flat
  widget set and page layout every module describes its settings with.
- `Overview.lua` — the Overview tab's content, plus the one-button stub page in
  Interface → AddOns that opens the real window.
- `Modules/<Name>.lua` — one file per utility. Contains the behavior AND its
  `M:BuildSettings(page)`.

## Settings live in HKSuite's own window, not Interface Options
`SettingsUI.lua` owns the whole settings surface: a standalone window with a rail
of modules down the left (each with its own on/off switch and a scope control)
and the selected module's page on the right. Interface → AddOns keeps a single
stub page whose only job is to open that window. `/hk` toggles it; `/hk <key>`
jumps straight to a module.

Modules **describe** their settings instead of positioning frames. `ns.UI` gives
you `page:Header/Text/Hint/Divider/Spacer`, `page:Check/Input/TextArea/Dropdown/
Slider/Button`, plus `page:Row` (side by side) and `page:Grid` (labelled dropdown
grid). Never build a Blizzard options panel and never call
`InterfaceOptions_AddCategory` from a module.

For a feature with a lot of settings, use `page:Section{title, get, set,
onChange}` instead of `page:Header` — a collapsible block whose header carries
the feature's on/off switch, folded shut by default, and which dims everything
inside it when switched off (no `BindChildren` needed). One rule comes with it:
**once a page opens its first section, everything after it must live in a
section too**, because sections own their contents in a container frame of their
own while plain content sits on the page flow. Small features stay plain headers.

## Rule: every new module MUST follow the registration convention
A module appears in the rail automatically as long as it registers with a `key`
and `title` — Core iterates `ns.modules`.

When creating a new module:

1. Register it with `key`, `title`, and `desc`:
   ```lua
   local ADDON, ns = ...
   local M = ns.RegisterModule({
       key   = "mymodule",                 -- unique; also its SavedVariables sub-table
       title = "My Module",                -- shown in the rail and as the page title
       desc  = "One-line description.",    -- shown under the page title
       -- reloadOnToggle = true,           -- if flipping the switch needs a reload
   })
   ```
2. Declare defaults under that key: `ns.defaults.mymodule = { enabled_thing = true }`.
3. In `M:OnInit()`, read the config via **`ns.GetConfig("mymodule")`** (NOT
   `ns.config.mymodule` directly — the resolver returns the account or
   per-character table based on the module's scope). Register events, and
   **guard all behavior** behind the module toggle so the rail switch works:
   ```lua
   frame:SetScript("OnEvent", function(_, event, ...)
       if ns.IsModuleEnabled("mymodule") then handlers[event](...) end
   end)
   ```
4. Describe its settings page. It is built lazily, the first time the module is
   selected:
   ```lua
   function M:BuildSettings(page)
       page:Header("Section")
       page:Check({
           label = "Do the thing", tooltip = "What it does.",
           get = function() return cfg.thing end,
           set = function(v) cfg.thing = v end,
           onChange = ApplyThing,          -- optional
       })
   end
   ```
5. Add the file to `HKSuite.toc` (after `Overview.lua`).

If the switch can't take effect immediately (the module only wires things up at
load), set `reloadOnToggle = true` so the window raises its reload banner, or
implement `M:OnToggle(enabled)` to apply it live — `Modules/AddonButton.lua` does
the latter, `Modules/Social.lua` the former.

See `Modules/QuestAutomation.lua` as the reference implementation.

## Rule: modules are listed alphabetically
The Overview list and the Interface Options sub-pages must stay in **alphabetical
order by module title**. This is handled centrally — Core sorts `ns.modules` by
`title` before building the Overview and calling `OnInit` — so a new module slots
into the right place automatically just by having a `title`. Don't rely on toc
load order for display order.

## Settings scope (account vs per-character)
Settings live in `HKSuiteDB` (account, `## SavedVariables`) or `HKSuiteCharDB`
(per-character, `## SavedVariablesPerCharacter`). Each character chooses, per
module, which to use via the "Shared" toggle on the Overview (default: account).
Modules must read config through `ns.GetConfig(key)` and check
`ns.IsModuleEnabled(key)` — both are scope-aware. Scope changes take effect after
a reload (modules capture their config table once at load), so `ns.SetScope`
callers should follow up with `ns.PromptReload()`.

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

## Rule: releases start as alpha, promote when confirmed
Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which publishes the
release as a **pre-release** (alpha) titled `HKSuite vX.Y.Z (alpha)`. It stays
alpha until the user confirms it works in-game, then promote it to Latest:

```
"C:\Program Files\GitHub CLI\gh.exe" release edit vX.Y.Z --prerelease=false --latest
```

Don't mark a release Latest until the user has confirmed that version.

## Rule: deploy to the game after every change
Whenever addon files change, copy the whole `HKSuite` folder into the live client
AddOns directory so it can be tested in-game:

```
C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns\HKSuite
```

PowerShell:
```powershell
robocopy "c:\Projects\HKSuite" "C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns\HKSuite" /MIR /XD ".git" ".github" /NFL /NDL /NJH /NJS
```
(`/MIR` mirrors the folder, so deletions/renames are reflected too. Run it from
**PowerShell**, not Git Bash — bash mangles the `/MIR` flags into paths. `/XD`
excludes the `.git`/`.github` dev folders from the game copy.)

After copying, the game must reload to pick up Lua changes: `/reload` in-game, or
log out to character select and back in. New/removed files require a full client
restart.

## Rule: never commit or push personal info
The repo is public. Before staging, committing, or pushing, make sure no personal
or machine-specific data goes in. This includes:

- **Absolute local paths** — `C:\Users\<name>\...`, `c:\Projects\...`,
  `C:\Ascension\...`, or any drive-letter path. Keep them out of committed files
  (docs like this one are the exception; source/config must not hardcode them).
- **Real-world identity** — personal email addresses, full names, account names,
  Discord/Battle.net handles, machine/host names.
- **Live game data** — never commit `HKSuiteDB` / `HKSuiteCharDB` SavedVariables,
  WTF/account folders, screenshots, logs, or anything copied out of the client.
- **Secrets** — tokens, API keys, GitHub credentials.

`.gitignore` is the first line of defense — verify anything sensitive is listed
there. Before every push, sanity-check `git status` / `git diff --staged` and stop
if personal info appears. When in doubt, leave it out and ask.

## Conventions
- Settings are built with `ns.UI` page methods so styling stays consistent.
- Colored addon-name prefix for chat output via `ns.Print`.
- Keep behavior modules self-contained: events + options panel in the one file.
