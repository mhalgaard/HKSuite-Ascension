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

local ddCount = 0
local function CreateDropdown(parent, width, options, getVal, setVal)
    ddCount = ddCount + 1
    local dd = CreateFrame("Frame", "HKSuiteLootDD" .. ddCount, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    local labelMap = {}
    for _, o in ipairs(options) do labelMap[o[1]] = o[2] end
    UIDropDownMenu_SetText(dd, labelMap[getVal()] or options[1][2])
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, o in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = o[2]
            info.value = o[1]
            info.checked = (getVal() == o[1])
            info.func = function(btn)
                setVal(btn.value)
                UIDropDownMenu_SetText(dd, labelMap[btn.value])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    return dd
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Loot Auto Roller"
    panel.parent = "HKSuite"

    -- Scrollable content (there are a lot of controls).
    local scroll = CreateFrame("ScrollFrame", "HKSuiteLootScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 860)
    scroll:SetScrollChild(content)

    local COLX = { 12, 175, 338 }   -- 3 columns
    local y = -8

    local function Title(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", COLX[1] - 4, y)
        fs:SetText(text)
        y = y - 30
    end
    local function Header(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", COLX[1] - 4, y)
        fs:SetText("|cffffd100" .. text .. "|r")
        y = y - 22
    end
    local function SubHeader(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", COLX[1] + 6, y)
        fs:SetText("|cffbbbbbb" .. text .. "|r")
        y = y - 18
    end
    local function Note(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", COLX[1], y)
        fs:SetWidth(500)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        y = y - 34
    end
    local function Check(label, tip, key)
        local cb = ns.CreateCheck(content, label, tip, cfg[key])
        cb:SetPoint("TOPLEFT", COLX[1] - 4, y)
        cb:SetScript("OnClick", function(self) cfg[key] = self:GetChecked() and true or false end)
        y = y - 26
    end
    -- Place a row of up to 3 labeled dropdowns; each item = {label,color,options,get,set}.
    local function Row(items)
        for i, it in ipairs(items) do
            local x = COLX[i]
            local lbl = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", x + 18, y)
            lbl:SetText(it.label)
            if it.color then lbl:SetTextColor(it.color[1], it.color[2], it.color[3]) end
            local dd = CreateDropdown(content, 84, it.options, it.get, it.set)
            dd:SetPoint("TOPLEFT", x, y - 15)
        end
        y = y - 54
    end

    -- Helpers to build per-table dropdown entries.
    local function qEntry(tbl, q, opts)
        return {
            label = QUALITY_LABEL[q], color = QColor(q), options = opts,
            get = function() return tbl[q] end,
            set = function(v) tbl[q] = v end,
        }
    end
    local function itemEntry(e)
        return {
            label = e.label, color = { 1, 1, 1 }, options = OVR_OPTS,
            get = function() return cfg.items[e.key] end,
            set = function(v) cfg.items[e.key] = v end,
        }
    end

    Title("Loot Auto Roller")

    Check("Also auto-roll on Bind-on-Pickup items",
        "When off, BoP items are left for you to roll manually.", "rollOnBoP")
    Check("Auto greed when an item cannot be disenchanted",
        "If a 'Disenchant' choice can't be disenchanted, greed it instead.", "greedIfNotDisenchant")
    Check("Auto greed when an item cannot be need rolled",
        "If a 'Need' choice can't be needed, greed it instead.", "greedIfCantNeed")
    Check("Skip bind-on-pickup roll confirmation",
        "Automatically confirm the BoP prompt for rolls this addon casts.", "skipBoPConfirm")

    Header("Items by Quality")
    Row({ qEntry(cfg.quality, 2, BASE_OPTS), qEntry(cfg.quality, 3, BASE_OPTS), qEntry(cfg.quality, 4, BASE_OPTS) })
    Row({ qEntry(cfg.quality, 5, BASE_OPTS), qEntry(cfg.quality, 6, BASE_OPTS) })

    Header("Overrides")
    Note("Options below override the choices above. For example, setting Epic Mystic Scrolls to Need will need them even if Epic is set to something else above.")

    SubHeader("Mystic Scrolls")
    Row({ qEntry(cfg.mystic, 2, OVR_OPTS), qEntry(cfg.mystic, 3, OVR_OPTS), qEntry(cfg.mystic, 4, OVR_OPTS) })
    Row({ qEntry(cfg.mystic, 5, OVR_OPTS) })

    SubHeader("Worldforged Scrolls")
    Row({ qEntry(cfg.worldforged, 3, OVR_OPTS), qEntry(cfg.worldforged, 4, OVR_OPTS), qEntry(cfg.worldforged, 5, OVR_OPTS) })

    Header("Specific Item Types")
    -- group entries by section, preserving order
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
        Row(entries)
    end
    for _, sec in ipairs(order) do
        SubHeader(sec)
        local entries = {}
        for _, e in ipairs(sections[sec]) do entries[#entries + 1] = itemEntry(e) end
        Row(entries)
    end

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.config.lootroll
    BuildOptionsPanel()

    local f = CreateFrame("Frame")
    f:RegisterEvent("START_LOOT_ROLL")
    f:RegisterEvent("CONFIRM_LOOT_ROLL")
    f:SetScript("OnEvent", function(_, event, id, rollType)
        if event == "START_LOOT_ROLL" then
            DoRoll(id)
        elseif event == "CONFIRM_LOOT_ROLL" then
            if autoRolled[id] and cfg.skipBoPConfirm then   -- only confirm our own rolls
                ConfirmLootRoll(id, rollType)
                autoRolled[id] = nil
            end
        end
    end)
end
