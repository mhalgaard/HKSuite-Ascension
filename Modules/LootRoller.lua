local ADDON, ns = ...

-- =============================================================================
-- Loot Auto Roller module.
-- Standard group-loot API (START_LOOT_ROLL / RollOnLoot / CONFIRM_LOOT_ROLL).
-- Ascension adds quality 6 ("Vanity", gold), which is included below.
--
-- Decision priority for each rolled item:
--   1. Specific item-type override (matched by name)
--   2. Mystic Scroll override (by quality)
--   3. Worldforged Scroll override (by quality)
--   4. Base "items by quality" setting
-- =============================================================================

local M = ns.RegisterModule({
    key   = "lootroll",
    title = "Loot Auto Roller",
    desc  = "Automatically pass/greed/disenchant/need on loot rolls, by item quality.",
    defaultEnabled = false,
})

-- Specific item-type overrides, matched by (lowercased) name substring.
-- `match` fields are best-effort; adjust if a server item name differs.
local SPECIFIC_ITEMS = {
    { key = "wfKeyFragments", label = "Worldforged Key Fragments", match = "worldforged key", default = "need" },
    { key = "doomshot",       label = "Doomshot",                  match = "doomshot",        default = "need" },
    { key = "cannonballs",    label = "Miniature Cannon Balls",    match = "miniature cannon", default = "need" },
    -- Zul'Gurub
    { key = "zgCoins",  label = "Coins",               match = "coin",         section = "Zul'Gurub", default = "none" },
    { key = "zgBijous", label = "Bijous",              match = "bijou",        section = "Zul'Gurub", default = "none" },
    { key = "zgIdols",  label = "Primal Hakkari Idols", match = "hakkari idol", section = "Zul'Gurub", default = "none" },
    -- Molten Core
    { key = "mcFiery",    label = "Fiery Cores",    match = "fiery core",    section = "Molten Core", default = "none" },
    { key = "mcLava",     label = "Lava Cores",     match = "lava core",     section = "Molten Core", default = "none" },
    { key = "mcSulfuron", label = "Sulfuron Ingots", match = "sulfuron ingot", section = "Molten Core", default = "none" },
    -- Blackwing Lair
    { key = "bwlHourglass",  label = "Hourglass Sand", match = "hourglass sand", section = "Blackwing Lair", default = "none" },
    { key = "bwlElementium", label = "Elementium Ore", match = "elementium ore", section = "Blackwing Lair", default = "none" },
}

local itemDefaults = {}
for _, e in ipairs(SPECIFIC_ITEMS) do itemDefaults[e.key] = e.default end

ns.defaults.lootroll = {
    rollOnBoP            = false,  -- when off, BoP items are left for manual rolling
    greedIfNotDisenchant = true,   -- greed when a "disenchant" item can't be DE'd
    greedIfCantNeed      = true,   -- greed when a "need" item can't be needed
    skipBoPConfirm       = true,   -- auto-confirm the BoP roll dialog, ours and manual rolls alike

    -- Base action by quality (Uncommon..Vanity).
    quality = {
        [2] = "greed",   -- Uncommon
        [3] = "none",    -- Rare
        [4] = "none",    -- Epic
        [5] = "none",    -- Legendary
        [6] = "greed",   -- Vanity (Ascension)
    },
    -- Mystic Scroll overrides (Uncommon..Legendary).
    mystic = { [2] = "greed", [3] = "greed", [4] = "greed", [5] = "greed" },
    -- Worldforged Scroll overrides (Rare..Legendary).
    worldforged = { [3] = "greed", [4] = "greed", [5] = "greed" },
    -- Specific item overrides.
    items = itemDefaults,
}

local cfg
local autoRolled = {}    -- rollIDs we initiated, so we only take their bars down

-- ------------------------------------------------------------ name matching
local function NameMatches(name, needle)
    return name and needle and name:lower():find(needle, 1, true) ~= nil
end
local function IsMysticScroll(name)
    return NameMatches(name, "mystic") and NameMatches(name, "scroll")
end
local function IsWorldforgedScroll(name)
    return NameMatches(name, "worldforged") and NameMatches(name, "scroll")
end

-- Resolve the action for an item, applying overrides in priority order.
local function ResolveAction(name, quality)
    -- 1. Specific item types.
    for _, e in ipairs(SPECIFIC_ITEMS) do
        local ov = cfg.items[e.key]
        if ov and ov ~= "none" and NameMatches(name, e.match) then
            return ov
        end
    end
    -- 2. Mystic scrolls.
    if IsMysticScroll(name) then
        local ov = cfg.mystic[quality]
        if ov and ov ~= "none" then return ov end
    end
    -- 3. Worldforged scrolls.
    if IsWorldforgedScroll(name) then
        local ov = cfg.worldforged[quality]
        if ov and ov ~= "none" then return ov end
    end
    -- 4. Base quality.
    return cfg.quality[quality]
end

-- An item you tell the roller to Need or Greed is an item you want, so the auto
-- seller must not vendor it -- rolling for Bijous and then selling them is the
-- case that prompted this. Pass and Disenchant are left out: neither ends with the
-- item in your bags on purpose.
--
-- Exported rather than duplicated because the match strings live here.
-- Modules/Automation.lua loads before this file, so it looks the function up when
-- it builds a sell plan rather than holding a reference. The answer comes from the
-- configured overrides whether or not the roller module is switched on: the
-- setting is a statement about the item, not about the automation.
local KEEP_ACTIONS = { need = true, greed = true }

-- Returns the label of the override keeping this item, or nil if none does.
function ns.LootRollKeeps(itemName)
    if not itemName then return end
    local conf = cfg or ns.GetConfig("lootroll")
    if not (conf and conf.items) then return end
    local lower = itemName:lower()
    for _, e in ipairs(SPECIFIC_ITEMS) do
        if KEEP_ACTIONS[conf.items[e.key] or ""] and lower:find(e.match, 1, true) then
            return e.label
        end
    end
end

local After = ns.After

-- Hide/release the group-loot window for a rollID. The default UI hides it in
-- the roll buttons' OnClick; since we call RollOnLoot directly we must do it.
-- ElvUI replaces the frames with its own bars (Misc.RollBars) that it only
-- releases on CANCEL_LOOT_ROLL, so we release its bar via its module API too.

-- Default Blizzard group-loot frames.
local function HideBlizzardRollFrame(rollID)
    local handled = false
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if f and f.rollID == rollID then
            f:Hide()
            handled = true
        end
    end
    return handled
end

-- ElvUI: release its loot bar for this rollID (frees it for reuse + hides).
local function ReleaseElvUIRollBar(rollID)
    local Misc = ElvUI and ElvUI[1] and ElvUI[1]:GetModule("Misc", true)
    if not (Misc and Misc.RollBars) then return false end
    for _, frame in ipairs(Misc.RollBars) do
        if frame.rollID == rollID then
            if Misc.ReleaseFrame then pcall(Misc.ReleaseFrame, Misc, frame)
            else pcall(frame.Hide, frame) end
            -- ElvUI stamps the rollID on the bar's icon button too (it owns the
            -- item tooltip) but ReleaseFrame only clears the bar's copy. Left
            -- behind, that stale id makes a dead bar match a later recycled
            -- rollID. Clear it, and make sure the icon is shown: ElvUI's
            -- START_LOOT_ROLL sets the icon's texture but never re-Shows it, so
            -- an icon hidden once stays hidden for the life of the bar.
            local icon = frame.itemButton
            if icon then
                icon.rollID = nil
                if icon.Show then pcall(icon.Show, icon) end
            end
            return true
        end
    end
    return false
end

-- Last resort for a replacement bar we don't know about.
--
-- A rollID is not unique to the bar: bars stamp it on the widgets inside as
-- well, so "hide everything carrying this id" is too blunt -- it takes the item
-- icon with it, and a pooled bar that gets recycled never shows that icon
-- again. Two rules keep this to the bar itself:
--   * IsVisible, not IsShown -- a child of an already-hidden bar still reports
--     IsShown() true, which is how released bars' icons were being hidden.
--   * skip any frame with an ancestor carrying the same rollID, so only the
--     outermost match is taken.
local function SweepRollFrames(rollID)
    if not EnumerateFrames then return end
    local f = EnumerateFrames()
    while f do
        if f.rollID == rollID and f.IsVisible and f:IsVisible() then
            local inside, parent = false, f.GetParent and f:GetParent()
            while parent do
                if parent.rollID == rollID then inside = true break end
                parent = parent.GetParent and parent:GetParent()
            end
            if not inside then pcall(f.Hide, f) end
        end
        f = EnumerateFrames(f)
    end
end

local function HideRollFrameNow(rollID)
    local blizz = HideBlizzardRollFrame(rollID)
    local elv = ReleaseElvUIRollBar(rollID)
    return blizz or elv
end

-- Our START_LOOT_ROLL handler can run either side of the one that builds the
-- bar, so if there's nothing to take down yet, look again shortly after. Only
-- fall through to the sweep once a retry has also come up empty -- a successful
-- release clears the rollID, and treating that as "not handled" is what sent
-- the sweep after the released bar's leftover widgets.
local function CloseRollFrame(rollID)
    if HideRollFrameNow(rollID) then return end
    After(0.1, function()
        if not HideRollFrameNow(rollID) then SweepRollFrames(rollID) end
    end)
end

-- Decide and cast the roll for a given rollID.
local function DoRoll(rollID)
    if not ns.IsModuleEnabled("lootroll") then return end
    local _, name, _, quality, bop, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if quality == nil then return end
    if bop and not cfg.rollOnBoP then return end   -- BoP protection

    local action = ResolveAction(name, quality)
    if not action or action == "none" then return end

    local rollType
    if action == "pass" then
        rollType = 0
    elseif action == "need" then
        if canNeed then
            rollType = 1
        elseif cfg.greedIfCantNeed and canGreed then
            rollType = 2
        else
            return   -- can't need and not greeding: leave for the player
        end
    elseif action == "greed" then
        rollType = canGreed and 2 or 0
    elseif action == "disenchant" then
        if canDisenchant then
            rollType = 3
        elseif cfg.greedIfNotDisenchant and canGreed then
            rollType = 2
        else
            return
        end
    else
        return
    end

    autoRolled[rollID] = true
    RollOnLoot(rollID, rollType)
    CloseRollFrame(rollID)
end

-- ============================== Options page =================================

local BASE_OPTS = { { "none", "No Auto Roll" }, { "pass", "Pass" }, { "greed", "Greed" }, { "disenchant", "Disenchant" }, { "need", "Need" } }
local OVR_OPTS  = { { "none", "No Override" },  { "pass", "Pass" }, { "greed", "Greed" }, { "disenchant", "Disenchant" }, { "need", "Need" } }

local QUALITY_LABEL = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Vanity" }

local function QColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return { c.r, c.g, c.b } end
    return { 1, 1, 1 }
end

function M:BuildSettings(page)
    local function Check(label, tip, key)
        page:Check({
            label = label, tooltip = tip,
            get = function() return cfg[key] end,
            set = function(v) cfg[key] = v end,
        })
    end

    -- Grid entries: one labelled dropdown per quality / per specific item type.
    local function qEntry(tbl, q, opts)
        return {
            label = QUALITY_LABEL[q], color = QColor(q), options = opts,
            get = function() return tbl[q] end,
            set = function(v) tbl[q] = v end,
        }
    end
    local function itemEntry(e)
        return {
            label = e.label, options = OVR_OPTS,
            get = function() return cfg.items[e.key] end,
            set = function(v) cfg.items[e.key] = v end,
        }
    end

    Check("Also auto-roll on Bind-on-Pickup items",
        "When off, BoP items are left for you to roll manually.", "rollOnBoP")
    Check("Auto greed when an item cannot be disenchanted",
        "If a 'Disenchant' choice can't be disenchanted, greed it instead.", "greedIfNotDisenchant")
    Check("Auto greed when an item cannot be need rolled",
        "If a 'Need' choice can't be needed, greed it instead.", "greedIfCantNeed")
    Check("Skip bind-on-pickup roll confirmation",
        "Automatically confirms the 'this item will bind to you' prompt -- both for rolls this "
        .. "addon casts and for Need / Greed / Disenchant you click yourself.", "skipBoPConfirm")

    page:Header("Items by quality")
    page:Grid(3, {
        qEntry(cfg.quality, 2, BASE_OPTS), qEntry(cfg.quality, 3, BASE_OPTS),
        qEntry(cfg.quality, 4, BASE_OPTS), qEntry(cfg.quality, 5, BASE_OPTS),
        qEntry(cfg.quality, 6, BASE_OPTS),
    })

    page:Header("Overrides")
    page:Text("These override the choices above. Setting Epic Mystic Scrolls to Need, for example, "
        .. "needs them even when Epic is set to something else.")

    page:Text("Mystic Scrolls")
    page:Grid(3, {
        qEntry(cfg.mystic, 2, OVR_OPTS), qEntry(cfg.mystic, 3, OVR_OPTS),
        qEntry(cfg.mystic, 4, OVR_OPTS), qEntry(cfg.mystic, 5, OVR_OPTS),
    })

    page:Text("Worldforged Scrolls")
    page:Grid(3, {
        qEntry(cfg.worldforged, 3, OVR_OPTS), qEntry(cfg.worldforged, 4, OVR_OPTS),
        qEntry(cfg.worldforged, 5, OVR_OPTS),
    })

    page:Header("Specific item types")
    -- Group by section (raid instance), preserving declaration order.
    local topRow, sections, order = {}, {}, {}
    for _, e in ipairs(SPECIFIC_ITEMS) do
        if e.section then
            if not sections[e.section] then sections[e.section] = {} order[#order + 1] = e.section end
            table.insert(sections[e.section], e)
        else
            table.insert(topRow, e)
        end
    end
    do
        local entries = {}
        for _, e in ipairs(topRow) do entries[#entries + 1] = itemEntry(e) end
        page:Grid(3, entries)
    end
    for _, sec in ipairs(order) do
        page:Text(sec)
        local entries = {}
        for _, e in ipairs(sections[sec]) do entries[#entries + 1] = itemEntry(e) end
        page:Grid(3, entries)
    end
end

-- Both confirmation events raise a static popup; a disenchant roll gets its own
-- dialog name. ElvUI runs its own popup system alongside Blizzard's, so ask both
-- to close. Hiding a dialog name that doesn't exist here is a no-op.
local CONFIRM_DIALOGS = { "CONFIRM_LOOT_ROLL", "CONFIRM_DISENCHANT_ROLL" }
local function HideConfirmPopups()
    local E = ElvUI and ElvUI[1]
    for _, dialog in ipairs(CONFIRM_DIALOGS) do
        StaticPopup_Hide(dialog)
        if E and E.StaticPopup_Hide then pcall(E.StaticPopup_Hide, E, dialog) end
    end
end

function M:OnInit()
    cfg = ns.GetConfig("lootroll")

    local f = CreateFrame("Frame", "HKSuiteLootRollerEvents")
    f:RegisterEvent("START_LOOT_ROLL")
    f:RegisterEvent("CONFIRM_LOOT_ROLL")
    f:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
    f:SetScript("OnEvent", function(_, event, id, rollType)
        if event == "START_LOOT_ROLL" then
            DoRoll(id)
        elseif cfg.skipBoPConfirm then
            -- Confirm whoever cast the roll: an item we skipped still needs the
            -- prompt cleared when the player clicks Need / Greed themselves.
            ConfirmLootRoll(id, rollType)
            HideConfirmPopups()
            -- Only our own rolls get their bar taken down. After a manual roll
            -- the bar stays up until the roll ends, same as any other item.
            if autoRolled[id] then
                autoRolled[id] = nil
                CloseRollFrame(id)
            end
        end
    end)
end
