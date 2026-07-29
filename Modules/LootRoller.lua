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
    skipBoPConfirm       = true,   -- auto-confirm the BoP roll confirmation dialog

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
local autoRolled = {}    -- rollIDs we initiated, so we only auto-confirm our own

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

-- One-shot delayed call (C_Timer when available, else an OnUpdate fallback).
local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn); return end
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= delay then self:SetScript("OnUpdate", nil); fn() end
    end)
end

-- Hide/release the group-loot window for a rollID. The default UI hides it in
-- the roll buttons' OnClick; since we call RollOnLoot directly we must do it.
-- ElvUI replaces the frames with its own bars (Misc.RollBars) that it only
-- releases on CANCEL_LOOT_ROLL, so we release its bar via its module API too.
--
-- A rollID is not unique to the bar: a replacement bar also stamps it on the
-- widgets inside, and ElvUI puts it on the bar's item icon (which is what owns
-- the item tooltip). So "hide everything carrying this id" is too blunt -- it
-- hid the icon as well, ElvUI's release only clears the id on the bar itself,
-- and recycling a bar never shows the icon again. Every auto-rolled item cost
-- one pooled bar its icon until the next reload. The sweep is now a last resort
-- for bars we don't know about, and it only takes the outermost match.
local function HideRollFrameNow(rollID)
    local handled = false

    -- Default Blizzard group-loot frames.
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if f and f.rollID == rollID then
            f:Hide()
            handled = true
        end
    end

    -- ElvUI: release its loot bar for this rollID (frees it for reuse + hides).
    local Misc = ElvUI and ElvUI[1] and ElvUI[1]:GetModule("Misc", true)
    if Misc and Misc.RollBars then
        for _, frame in ipairs(Misc.RollBars) do
            if frame.rollID == rollID then
                if Misc.ReleaseFrame then pcall(Misc.ReleaseFrame, Misc, frame)
                else pcall(frame.Hide, frame) end
                handled = true
                break
            end
        end
    end

    if handled or not EnumerateFrames then return end

    -- Unknown replacement bar. EnumerateFrames walks in creation order, so a
    -- parent always comes before its children -- which lets us hide a bar and
    -- then skip everything inside it.
    local hidden = {}
    local f = EnumerateFrames()
    while f do
        if f.rollID == rollID and f.IsShown and f:IsShown() then
            local inside, parent = false, f.GetParent and f:GetParent()
            while parent do
                if hidden[parent] then inside = true break end
                parent = parent.GetParent and parent:GetParent()
            end
            if not inside then
                hidden[f] = true
                pcall(f.Hide, f)
            end
        end
        f = EnumerateFrames(f)
    end
end

-- Run immediately (frames already built) and again shortly after, since a
-- replacement bar (ElvUI) may be created after our roll fires this same event.
local function CloseRollFrame(rollID)
    HideRollFrameNow(rollID)
    After(0.1, function() HideRollFrameNow(rollID) end)
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
        "Automatically confirm the BoP prompt for rolls this addon casts.", "skipBoPConfirm")

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

function M:OnInit()
    cfg = ns.GetConfig("lootroll")

    local f = CreateFrame("Frame")
    f:RegisterEvent("START_LOOT_ROLL")
    f:RegisterEvent("CONFIRM_LOOT_ROLL")
    f:SetScript("OnEvent", function(_, event, id, rollType)
        if event == "START_LOOT_ROLL" then
            DoRoll(id)
        elseif event == "CONFIRM_LOOT_ROLL" then
            if autoRolled[id] and cfg.skipBoPConfirm then   -- only confirm our own rolls
                ConfirmLootRoll(id, rollType)
                StaticPopup_Hide("CONFIRM_LOOT_ROLL")
                if ElvUI and ElvUI[1] and ElvUI[1].StaticPopup_Hide then
                    pcall(ElvUI[1].StaticPopup_Hide, ElvUI[1], "CONFIRM_LOOT_ROLL")
                end
                autoRolled[id] = nil
                CloseRollFrame(id)
            end
        end
    end)
end
