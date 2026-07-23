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

| Module | Default | Summary |
|---|---|---|
| Quest Automation | On | Auto accept / turn in / reward pick / gossip skip; daily & callboard toggles |
| Item Deletion | On | Auto-fills the DELETE prompt; optional instant delete |
| Social | On | Class colors, chat tabs, World channel, group-invite automation |
| System | On | Screen effects, weather, fast loot, BoP confirm, camera distance |
| Chat Filters | On *(filters off)* | Hide Ascension broadcast & channel spam |
| Clear Quests | On | Abandon unwanted quests, keeping the ones you choose |
| Addon Button | On | Consolidate minimap buttons into one HK flyout |
| Auto-Grab Vanity | On | Collect & tidy up vanity-collection items |
| Loot Auto Roller | Off | Auto-roll on group loot, by item quality |
| Auto Summon Pets | Off | Context-based premium-pet summoning |

<details>
<summary><b>Quest Automation</b></summary>

| Option | Default | What it does |
|---|---|---|
| Auto-accept quests | **On** | Accepts offered quests automatically (incl. shared/escort confirmations). |
| Auto turn in quests | Off | Hands in completed quests. Waits for you on reward-choice quests unless the sub-option below is on. |
| └ Auto-select most valuable reward | Off | On reward-choice quests, picks the highest vendor-value reward. Enabling it also enables Auto turn in. |
| Auto-skip single gossip option | Off | When an NPC has one gossip option and no quests to handle, selects it to skip the talk menu. |
| Don't auto-accept daily quests | Off | Skips auto-accepting quests flagged as daily. |
| Auto-accept callboard / command board quests | Off | Callboard/command board quests are not auto-accepted unless this is on. |

A **bypass key** (default: Shift) pauses all quest automation while held.
</details>

<details>
<summary><b>Item Deletion</b></summary>

| Option | Default | What it does |
|---|---|---|
| Auto-fill "DELETE" in deletion prompts | **On** | Pre-fills the required `DELETE` word, so it's one click to confirm. |
| Instant delete (skip the confirmation) | Off | Deletes immediately with no dialog. Use with care — deletions are unrecoverable. |
</details>

<details>
<summary><b>Social</b></summary>

- **Class colors** in all chat channels (default on).
- **Auto-join the World channel** on login (default on).
- **Chat font size** slider for all tabs (default 12).
- Auto-create configured chat tabs (per character):
  - **Guild** tab — all chat + XP/honor/rep/skill-ups/loot/money/system/errors/ignored (with an option to show only guild chat & whispers).
  - **World** tab — the Ascension / World / LookingForGroup / Trade channels + whispers.
  - **Loot** tab — item loot, money, rolls + whispers.
- **Group invites** — auto-accept invites from friends/guildmates; auto-invite anyone who whispers a keyword (default `inv`), optionally restricted to friends/guildmates.
</details>

<details>
<summary><b>System</b></summary>

| Option | Default | What it does |
|---|---|---|
| Disable screen glow | Off | Turns off the full-screen glow. |
| Disable screen effects | Off | Turns off the death / nether-world effects. |
| Set weather density to 0 | Off | Removes rain, snow and weather. |
| Enable fast auto loot | Off | Instantly loots corpses and objects. |
| Auto-confirm Bind-on-Pickup loot | Off | Confirms the BoP loot prompt for you, any quality. |
| Camera distance | — | Slider from minimum to maximum zoom. |
</details>

<details>
<summary><b>Chat Filters</b> <i>(all filters off by default)</i></summary>

Hide Ascension spam, grouped with an **All on / All off** toggle:
- **Rest areas:** hide /say and /yell while in a city.
- **System broadcasts:** trials/nightmares, mystic altars, autobroadcasts, travel guides, keeper's scrolls, motherlodes, criminal intent, hardcore, posture check, faction-leader spawns, and world-boss spawn alerts.
- **Channel spam:** `bau`, `dp` (not `dps`), `twitch`, `discord.gg` in public channels.
- **Default chat tab:** remove the Newcomers / Ascension / World channels.

(Ported from XanAscTweaks — disable that addon's overlapping options to avoid double behavior.)
</details>

<details>
<summary><b>Addon Button</b></summary>

A movable square **HK** button near the minimap consolidates other addons'
minimap buttons into one flyout. **Click** opens the menu, **Shift+click** opens
HKSuite options, **Shift+CTRL+right-click** clears quests (per Clear Quests
settings), and **CTRL+drag** moves it.
</details>

<details>
<summary><b>Clear Quests</b></summary>

Abandon unwanted quests in one click, keeping the ones you want:
- Keep completed / daily / dungeon / Path-to-Ascension quests, quests with
  progress, and anything on your **whitelist** (each toggleable, with separate
  "include trivial" sub-options).
- Prestige and Mentorship quests are always kept.
- **Clear quests now** button (asks for confirmation and lists what it will
  abandon). The HK button's **Shift+CTRL+right-click** does it instantly.
</details>

<details>
<summary><b>Auto-Grab Vanity</b></summary>

Collect and tidy up your vanity-collection items:
- **Grab unlearned vanity** — delivers vanity spells you own but haven't learned (also runs on login if enabled).
- **Grab Fel Enchanted Warchest** — delivers the Warchest if you own it.
- **Grab utility bundle** — delivers your owned utility vanity (anvils, call boards, altars, retreat scrolls, feather, raid markers).
- **Delete Fel Warchest items** — removes the Warchest's leftover items from your bags.
- **Delete collected vanity items** — removes bag vanity you already own in your collection.
- **Delete duplicate vanity items** — removes extra copies, keeping one of each.

All deletions ask for confirmation and never touch bag containers. (Grab logic ported from XanAscTweaks.)
</details>

<details>
<summary><b>Loot Auto Roller</b> <i>(default: disabled)</i></summary>

Auto-rolls on group loot by item quality (Uncommon → Vanity), with:
- Toggles: also roll BoP items; greed when an item can't be disenchanted; greed when it can't be need-rolled; skip the BoP roll confirmation.
- **Overrides** (take priority over the quality settings): per-quality actions for **Mystic Scrolls** and **Worldforged Scrolls**, and a **Specific Item Types** section (Worldforged Key Fragments, Doomshot, Miniature Cannon Balls, plus Zul'Gurub / Molten Core / Blackwing Lair item groups).
</details>

<details>
<summary><b>Auto Summon Pets</b> <i>(default: disabled)</i></summary>

Summons the right premium pet for your situation (Manastorm, dungeon, raid, open
world, safe zone), leaving PvP alone. On login, summons the best pet if none is
active. Options for combat / zone-change / recast delay, a Loot-Transfigurator
skip, and a custom safe-zone pet. (Wisdomball is only summoned in Normal dungeons.)
</details>

## Releases
Pushing a `vX.Y.Z` tag triggers a GitHub Action that packages the addon and
publishes a Release with a ready-to-extract zip. See `.github/workflows/release.yml`.

## Development
See `CLAUDE.md` for conventions. New modules register with a `key`/`title` (so
they appear on the Overview automatically) and add a settings sub-page; prototype
in `Modules/Scratch.lua` for `/reload`-only iteration, then promote to a dedicated
file. Reference implementation: `Modules/QuestAutomation.lua`.
