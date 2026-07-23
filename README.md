# HKSuite

A suite of quality-of-life utilities for **Project Ascension** (WoW 3.3.5a client).
Built to be modular — each utility is a self-contained module, so new tools drop
straight in.

## Overview page
The top-level **HKSuite** entry in Interface → AddOns is an Overview: a quick
enable/disable checkbox for every module. Each module's detailed settings live on
its own sub-page nested underneath.

## Modules

### Quest Automation
| Option | Default | What it does |
|---|---|---|
| Auto-accept quests | **On** | Accepts offered quests automatically (incl. shared/escort confirmations). |
| Auto turn in quests | Off | Hands in completed quests. Waits for you to choose on reward-choice quests unless the sub-option below is on. |
| └ Auto-select most valuable reward | Off | Sub-option of Auto turn in. On reward-choice quests, picks the highest vendor-value reward. Enabling it also enables Auto turn in. |
| Auto-skip single gossip option | Off | When an NPC has one gossip option and no quests to handle, selects it automatically to skip the talk menu. |

A **bypass key** (default: Shift) temporarily pauses all quest automation while
held, so you can talk to NPCs normally. Set it to None in the panel to disable.

### Item Deletion
| Option | Default | What it does |
|---|---|---|
| Auto-fill "DELETE" in deletion prompts | **On** | Pre-fills the required `DELETE` word when deleting a quality item, so it's a single click to confirm. |
| Instant delete (skip the confirmation) | Off | Deletes the item immediately with no dialog at all. Use with care. |

## Installation
1. Copy the whole `HKSuite` folder into:
   `World of Warcraft\Interface\AddOns\`
2. The folder **must** be named `HKSuite` (matching `HKSuite.toc`).
3. Restart the client (or `/reload`), and make sure HKSuite is enabled on the
   character-select AddOns list.

## Usage
Everything is configured in the UI: **Esc → Interface → AddOns → HKSuite**
(or type `/hk` to jump straight there). The bypass key is a dropdown in that
panel.

## Adding a module
Create `Modules\YourThing.lua`, register it in `HKSuite.toc`, and follow the
pattern in `Modules\QuestAutomation.lua`:

```lua
local ADDON, ns = ...
local M = ns.RegisterModule({})
ns.defaults.yourthing = { enabled = true }
function M:OnInit()
    local cfg = ns.config.yourthing
    -- create frames, register events, etc.
end
```
