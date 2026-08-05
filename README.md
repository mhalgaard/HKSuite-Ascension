# HKSuite

*HKSuite by Nodding*

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
| Automation | On *(actions off)* | Auto-release after death (BG/world/dungeon), auto-sell junk and auto-repair at vendors |
| Social | On | Class colors, chat tabs, World channel, group-invite automation |
| System | On | Screen/weather/loot tweaks, camera, error hiding, auto-dismount, item deletion |
| Chat Filters | On *(filters off)* | Hide Ascension broadcast & channel spam |
| Clear Quests | On | Abandon unwanted quests, keeping the ones you choose |
| UI Features | On *(features off)* | In-range crosshair, trinket cooldown tracker, on-screen stat readout, loot rolls under the objectives frame |
| Addon Button | On | Consolidate minimap buttons into one HK flyout |
| Auto-Grab Vanity | On | Collect & tidy up vanity-collection items |
| Loot Auto Roller | Off | Auto-roll on group loot, by item quality |
| Auto Summon Pets | Off | Context-based premium-pet summoning |
| Synergy Export | On | Export this character for the Ascension Synergy site |

<details>
<summary><b>Quest Automation</b></summary>

| Option | Default | What it does |
|---|---|---|
| Auto-accept quests | **On** | Accepts offered quests automatically (incl. shared/escort confirmations). |
| Auto turn in quests | Off | Hands in completed quests. Waits for you on reward-choice quests unless the sub-option below is on. |
| └ Auto-select most valuable reward | Off | On reward-choice quests, picks the highest vendor-value reward. Enabling it also enables Auto turn in. |
| Also open quests already in your log | Off | Lowest priority — once hand-ins and new quests are done, opens a quest you're already on. |
| Auto-skip single gossip option | Off | When an NPC has one gossip option and no quests to handle, selects it to skip the talk menu. |
| Don't auto-accept daily quests | Off | Skips auto-accepting quests flagged as daily. |
| Auto-accept callboard / command board quests | Off | Callboard/command board quests are not auto-accepted unless this is on. |
| Auto-share quests with your party | Off | Shares each accepted quest with your group (only quests that can be shared). |
| └ Party only — never share in a raid | **On** | Suppresses auto-sharing while you're in a raid group. |

Quest givers are handled in priority order — **completed hand-in → available quest →
quest already in your log** — one thing per interaction, so multi-quest NPCs drain a
step at a time.

A **bypass key** (default: Shift) pauses all quest automation while held.
</details>

<details>
<summary><b>Automation</b></summary>

**Auto release spirit** (waits briefly, and skips releasing if a resurrection is being offered or a soulstone is available):

| Option | Default | What it does |
|---|---|---|
| Auto release after death | Off | Master switch for auto-releasing your spirit. |
| └ In battlegrounds | On | Release automatically while in a battleground. |
| └ In the open world | On | Release automatically when you die out in the world. |
| └ In dungeons / raids | Off | Release in 5-mans/raids. Off by default so you can wait for a battle-res. |

**Auto sell at vendors** (only items with a vendor value are ever sold):

| Option | Default | What it does |
|---|---|---|
| Auto sell items when visiting a vendor | Off | On merchant open, sells the qualities selected below, minus anything a rule below or the never-sell list holds back. |
| └ Poor / Common / Uncommon / Rare / Epic | Poor + Common on | Per-quality sell toggles. |
| └ Collect the appearance before selling | Off | For each item the filter picked out, collects its transmog appearance first if you don't have it yet (confirming the dialog for you), then sells. Items the filter wouldn't sell are never collected; an item whose appearance can't be collected is left in your bags. |
| └ Never sell realm bound items | **On** | Protects anything whose tooltip says Realm Bound. |
| └ Never sell worldforged items | **On** | Protects anything whose tooltip says Worldforged. |
| └ Never sell trade goods / crafting materials | **On** | Protects ore, herbs, cloth, leather, enchanting mats and other Trade Goods / reagents from the quality rules. |
| &nbsp;&nbsp;&nbsp;&nbsp;└ …except Cloth / Leather / Metal & stone / Herbs / Meat / Enchanting / Elemental | All off | Tick a sub-category to sell it anyway. Matched by item sub-class, so it covers the whole category. |
| └ Never sell gemstones | **On** | Protects gems and pearls (Star Ruby, Small Lustrous Pearl, cut and uncut gems), matched by item class. |
| └ Never sell elixirs from level *N* | **On**, level 30 | Protects elixirs requiring at least level *N*, so low-level leftovers still sell. Flasks and potions aren't covered. |
| Never-sell list | — | Item names or IDs (one per line) that are never sold, whatever the quality rules say. Click into the box and **shift-click** an item to add it by name. |

**Auto repair at vendors:**

| Option | Default | What it does |
|---|---|---|
| Auto repair when visiting a vendor | Off | Repairs all gear at merchants that can repair. Runs after auto-sell, so the proceeds help pay for it. |
| └ Use guild funds when available | **On** | Pays from the guild bank's repair allowance when your rank has one and it covers the bill; otherwise your own money is used. |
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
| Camera distance | — | Slider from minimum to maximum zoom. |
| Enable fast auto loot | Off | Instantly loots corpses and objects. |
| Auto-confirm Bind-on-Pickup loot | Off | Confirms the BoP loot prompt for you, any quality. |
| Hide on-screen error messages | Off | Hides the red error text in the middle of the screen. |
| Disable error sounds (cooldown / GCD) | Off | Silences the spoken error sounds when an ability isn't ready. |
| Dismount when using an action | Off | Dismounts when you cast a spell or use an item while mounted (never while flying). |
| Dismount at flight masters | Off | Dismounts when you open a flight master's map. |
| Auto-fill "DELETE" in deletion prompts | **On** | Pre-fills the required `DELETE` word, so it's one click to confirm. |
| Instant delete (skip the confirmation) | Off | Deletes immediately with no dialog. Use with care — deletions are unrecoverable. |
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

The flyout closes itself 5 seconds after the mouse leaves it (the button counts
as part of the menu, and the timer restarts every time you move back in).
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
<summary><b>UI Features</b> <i>(both features off by default)</i></summary>

| Option | Default | What it does |
|---|---|---|
| Enable in-range tracker | Off | Shows a crosshair over your character — white when your target is in melee range, red when out of range. |
| Enable trinket tracker | Off | Shows your equipped trinkets and their cooldowns in a box, greyed out while on cooldown. Hold **Ctrl + left-drag** to move it. |
| └ Show the countdown number | **On** | The number ticking down over the icon. Off, the cooldown sweep remains — handy if another addon already puts timers on cooldowns. |
| Enable stat display | Off | Your stats as plain text on screen, one colour each — Str/AP red, Agi/crit green, Int/SP blue, Spirit white, Stamina gold, hit orange, expertise purple. Hold **Ctrl + left-drag** to move it. |
| └ Strength / Agility / Stamina / Intellect / Spirit | Sta off, rest on | Per-stat toggles for the primary stats. |
| └ Attack power / Spell power | **On** | Melee attack power; spell power is the best school, as the paper doll shows it. |
| └ Melee crit % / Spell crit % | Melee on | Crit chance. |
| └ Melee hit % / Spell hit % | Melee on | Hit from rating, plus whatever talents and gear add flat. |
| └ Expertise | **On** | Expertise points. |
| └ Hide stats sitting at zero | **On** | A stat with no value drops out instead of taking up a line — handy on a classless server. |
| └ Lock in place | Off | Locked, it takes no mouse input, so clicks pass straight through it. |
| └ Layout | Vertical list | Vertical list (values right-aligned in a column) or one row. |
| └ Font size | 12 | 8–24. |
| Show the loot rolls list | Off | A "Loot Rolls" block under the objectives frame listing what your group most recently rolled on. Click an item to see every player's choice. |
| └ Attach to the objectives frame | **On** | On: sits underneath your tracked quests, styled like one of the tracker's own blocks. Off: a free-floating box you move with **Ctrl + left-drag**. |
| └ Limit the quests the tracker lists | **On**, 5 | Caps how many quests the objectives frame draws so the loot rolls block stays in view. The rest stay tracked, they're just not listed. |
| └ List players who passed | **On** | Include players who passed in the expanded list. |
| └ Items to list | 4 | How many recent items the block shows. |
| └ Hide the list after *N* seconds | 120 | Hides the block once the newest roll has been finished this long (0 = never). |

Melee range is exact: it uses `IsSpellInRange` with a real 5-yard melee ability. Since Ascension is classless, the tracker auto-detects a melee ability you know from a built-in list — or you can type a specific ability name in the module options. If no melee ability is found it falls back to a coarse ~9.9 yd distance check.
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

<details>
<summary><b>Synergy Export</b></summary>

Produces a copy-pasteable block describing this character for the **Ascension
Synergy** site's Import character panel. Hit **Generate export**, then click the
box, Ctrl+A, Ctrl+C.

It's plain `key=value` text rather than a binary blob, so you can read exactly
what's being shared. Included:
- **Character stats** *(optional)* — level, applied Path, primary stats (both
  unbuffed base and current, with a flag if buffs were up), attack/ranged power,
  spell power, crit, weapon damage and speeds, and the level's AE/TE budgets.
- **Abilities and talents** — everything you've learned, with ranks.
- **In-game build code** *(optional)* — the game's own `ExportBuild` string, so
  the build can be re-imported in game.
</details>

## Releases
Pushing a `vX.Y.Z` tag triggers a GitHub Action that packages the addon and
publishes a Release with a ready-to-extract zip. See `.github/workflows/release.yml`.

## Credits
**HKSuite by Nodding.** Bug reports and suggestions are welcome on the
[issue tracker](https://github.com/mhalgaard/HKSuite-Ascension/issues).

Third-party code this suite builds on:
- **Auto-Grab Vanity** — grab logic ported from *XanAscTweaks*.

## Development
See `CLAUDE.md` for conventions. New modules register with a `key`/`title` (so
they appear on the Overview automatically) and add a settings sub-page; prototype
in `Modules/Scratch.lua` for `/reload`-only iteration, then promote to a dedicated
file. Reference implementation: `Modules/QuestAutomation.lua`.
