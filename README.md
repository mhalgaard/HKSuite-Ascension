# HKSuite

A suite of quality-of-life utilities for **Project Ascension** (WoW 3.3.5a client).
Built to be modular — each utility is a self-contained module, so new tools drop
straight in. All settings are **account-wide** (shared across every character).

## Installation
1. Download the latest `HKSuite-vX.Y.Z.zip` from the
   [Releases page](https://github.com/mhalgaard/HKSuite-Ascension/releases).
2. Extract it into `World of Warcraft\Interface\AddOns\` — it contains a single
   `HKSuite` folder (the folder **must** stay named `HKSuite`).
3. Restart the client and make sure HKSuite is enabled on the character-select
   AddOns list.

## Usage
Everything is configured in the UI: **Esc → Interface → AddOns → HKSuite**, or
type **`/hk`**. `/rl` is a shortcut for `/reload` (only if no other addon claims
it). The top-level **HKSuite** page is an Overview with an enable/disable toggle
for every module; each module has its own settings sub-page.

### Account-wide vs per-character
Settings are **account-wide by default** (shared across all characters). On the
Overview, each module has a **Shared** checkbox — uncheck it to give the current
character its own settings for that module (seeded from the account settings).
Bulk **All shared** / **All per-character** buttons are provided. Scope changes
apply after a reload.

## Modules

### Quest Automation
| Option | Default | What it does |
|---|---|---|
| Auto-accept quests | **On** | Accepts offered quests automatically (incl. shared/escort confirmations). |
| Auto turn in quests | Off | Hands in completed quests. Waits for you on reward-choice quests unless the sub-option below is on. |
| └ Auto-select most valuable reward | Off | On reward-choice quests, picks the highest vendor-value reward. Enabling it also enables Auto turn in. |
| Auto-skip single gossip option | Off | When an NPC has one gossip option and no quests to handle, selects it to skip the talk menu. |
| Don't auto-accept daily quests | Off | Skips auto-accepting quests flagged as daily. |
| Auto-accept callboard / command board quests | Off | Callboard/command board quests are not auto-accepted unless this is on. |

A **bypass key** (default: Shift) pauses all quest automation while held.

### Item Deletion
| Option | Default | What it does |
|---|---|---|
| Auto-fill "DELETE" in deletion prompts | **On** | Pre-fills the required `DELETE` word, so it's one click to confirm. |
| Instant delete (skip the confirmation) | Off | Deletes immediately with no dialog. Use with care — deletions are unrecoverable. |

### Social
- **Class colors** in all chat channels (default on).
- **Auto-join the World channel** on login (default on).
- **Chat font size** slider for all tabs (default 12).
- Auto-create configured chat tabs (checked-and-created on login, per character):
  - **Guild** tab — all chat + XP/honor/rep/skill-ups/loot/money/system/errors/ignored (with an option to show only guild chat & whispers).
  - **World** tab — the Ascension / World / LookingForGroup / Trade channels + whispers.
  - **Loot** tab — item loot, money, rolls (system) + whispers.
- **Group invites**: auto-accept invites from friends/guildmates; auto-invite anyone who whispers a keyword (default `inv`), optionally restricted to friends/guildmates.

### System
| Option | Default | What it does |
|---|---|---|
| Disable screen glow | Off | `ffxGlow` off. |
| Disable screen effects | Off | Death/nether effects off (`ffxDeath`, `ffxNetherWorld`). |
| Set weather density to 0 | Off | Removes rain/snow/weather. |
| Enable fast auto loot | Off | Instantly loots on opening a corpse/object. |
| Auto-confirm Bind-on-Pickup loot | Off | Auto-confirms the BoP loot prompt, any quality. |
| Camera distance | — | Slider (Min→Max); only manages the CVar once moved. |

### Loot Auto Roller  *(default: disabled)*
Auto-rolls on group loot by item quality (Uncommon → Vanity), with:
- Toggles: also roll BoP items; greed when an item can't be disenchanted; greed when it can't be need-rolled; skip the BoP roll confirmation.
- **Overrides** (take priority over the quality settings): per-quality actions for **Mystic Scrolls** and **Worldforged Scrolls**, and a **Specific Item Types** section (Worldforged Key Fragments, Doomshot, Miniature Cannon Balls, plus Zul'Gurub / Molten Core / Blackwing Lair item groups) — matched by item name.

### Auto Summon Pets  *(default: disabled)*
Summons the right premium pet for your situation (Manastorm, dungeon, raid, open
world, safe zone), leaving PvP alone. On login, summons the best pet if none is
active. Options for combat/zone-change/recast-delay, a Loot-Transfigurator skip,
and a custom safe-zone pet. (Wisdomball is only summoned in Normal dungeons.)

### Addon Button
A movable square **HK** button near the minimap consolidates other addons'
minimap buttons into one flyout. Click to open the menu, **Shift+click** for
HKSuite options, **CTRL+drag** to move it.

## Releases
Pushing a `vX.Y.Z` tag triggers a GitHub Action that packages the addon and
publishes a Release with a ready-to-extract zip. See `.github/workflows/release.yml`.

## Development
See `CLAUDE.md` for conventions. New modules register with a `key`/`title` (so
they appear on the Overview automatically) and add a settings sub-page; prototype
in `Modules/Scratch.lua` for `/reload`-only iteration, then promote to a dedicated
file. Reference implementation: `Modules/QuestAutomation.lua`.
