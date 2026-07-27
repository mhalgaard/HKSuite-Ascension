local ADDON, ns = ...

-- =============================================================================
-- Automation module: hands-off conveniences.
--   * Auto release spirit after death (per zone type: BG / world / dungeon).
--   * Auto sell junk (and optionally other qualities / a whitelist) at vendors.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "automation",
    title = "Automation",
    desc  = "Auto-release after death and auto-sell junk at vendors.",
})

ns.defaults.automation = {
    -- Auto release
    autoRelease    = false,   -- master switch for auto releasing spirit
    releaseBG      = true,     -- release in battlegrounds
    releaseWorld   = true,     -- release out in the open world
    releaseDungeon = false,    -- release in 5-mans / raids (off: battle-rez friendly)
    releaseDelay   = 0.6,      -- seconds to wait after death before releasing

    -- Auto sell
    autoSell    = false,       -- master switch for auto selling at vendors
    sellQuality = {            -- which item qualities to auto-sell
        [0] = true,            -- Poor (junk)
        [1] = true,            -- Common
        [2] = false,           -- Uncommon
        [3] = false,           -- Rare
        [4] = false,           -- Epic
    },
    -- Protections: item categories the quality rules above are not allowed to
    -- sell. The whitelist still overrides these.
    protectTradeGoods = true,  -- crafting materials (ore, herbs, cloth, leather, mats)
    protectGems       = true,  -- gemstones and pearls
    protectElixirs    = true,  -- elixirs from elixirMinLevel upwards
    elixirMinLevel    = 30,    -- required level an elixir must reach to be protected

    whitelist   = {},          -- item names or IDs to always sell, regardless of quality
}

local cfg  -- filled in OnInit

-- One-shot delayed call. Uses C_Timer when the client provides it, otherwise
-- falls back to a self-cancelling OnUpdate.
local function After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
        return
    end
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

-- ------------------------------------------------------------------ auto release
-- A resurrect offer is up (someone is battle-rezzing us) -> don't auto-release.
local function ResurrectPending()
    return StaticPopup_Visible("RESURRECT")
        or StaticPopup_Visible("RESURRECT_NO_SICKNESS")
        or StaticPopup_Visible("RESURRECT_NO_TIMER")
end

local handlers = {}

function handlers.PLAYER_DEAD()
    if not cfg.autoRelease then return end

    local _, instanceType = IsInInstance()   -- "none" / "pvp" / "arena" / "party" / "raid"
    local shouldRelease =
        (instanceType == "pvp" and cfg.releaseBG)
        or (instanceType == "none" and cfg.releaseWorld)
        or ((instanceType == "party" or instanceType == "raid") and cfg.releaseDungeon)
    if not shouldRelease then return end

    After(cfg.releaseDelay or 0.6, function()
        if not ns.IsModuleEnabled("automation") or not cfg.autoRelease then return end
        if not UnitIsDeadOrGhost("player") then return end   -- resurrected already
        if UnitIsGhost("player") then return end              -- already released
        if HasSoulstone() then return end                     -- can self-res; leave it to the player
        if ResurrectPending() then return end                 -- someone is rezzing us
        RepopMe()
    end)
end

-- ------------------------------------------------------------------ auto sell
-- Build fast lookups from the whitelist (numeric entries -> item IDs,
-- everything else -> lowercased item names).
local function BuildWhitelist()
    local ids, names = {}, {}
    for _, entry in ipairs(cfg.whitelist) do
        local num = tonumber(entry)
        if num then
            ids[num] = true
        else
            names[entry:lower()] = true
        end
    end
    return ids, names
end

-- ---------------------------------------------------------------- protections
-- Item categories the quality rules aren't allowed to sell. Each group matches
-- on the item's class (or sub-class) rather than on a name list, so one entry
-- covers a whole category: every profession's materials live under Trade Goods,
-- every gemstone under the gem class, every elixir under the Elixir sub-class.
--
-- GetItemInfo gives only the *localized* class names on this client (3.3.5
-- returns no numeric class id), so instead of hardcoding "Trade Goods" each
-- group learns its names from reference items -- real items known to be in the
-- category. The English names seed each set so a group still works before the
-- client has cached its references.
local PROTECTIONS = {
    {
        key    = "materials",
        option = "protectTradeGoods",
        label  = "trade good",
        field  = "class",
        names  = { ["trade goods"] = true, ["reagent"] = true },
        refs   = {
            2589,    -- Linen Cloth     (Trade Goods / Cloth)
            2318,    -- Light Leather   (Trade Goods / Leather)       -- skinning
            2770,    -- Copper Ore      (Trade Goods / Metal & Stone) -- mining
            2447,    -- Peacebloom      (Trade Goods / Herb)          -- herbalism
            10940,   -- Strange Dust    (Trade Goods / Enchanting)    -- enchanting
        },
    },
    {
        key    = "gems",
        option = "protectGems",
        label  = "gem",
        field  = "class",
        names  = { ["gem"] = true },
        refs   = {
            1529,    -- Star Ruby
            5498,    -- Small Lustrous Pearl
            36929,   -- Scarlet Ruby        (a cut Wrath gem, in case the classes differ)
        },
    },
    {
        key      = "elixirs",
        option   = "protectElixirs",
        label    = "elixir",
        field    = "subclass",
        names    = { ["elixir"] = true },
        minLevel = "elixirMinLevel",
        refs     = {
            2454,    -- Elixir of Lion's Strength
            13452,   -- Elixir of the Mongoose
        },
    },
}

local resolved = false

-- Learn each group's class names from its reference items, retrying on later
-- vendor visits until every reference has been cached by the client.
local function ResolveClassNames()
    if resolved then return end
    local allCached = true
    for _, group in ipairs(PROTECTIONS) do
        for _, id in ipairs(group.refs) do
            local _, _, _, _, _, itemType, itemSubType = GetItemInfo(id)
            local value = (group.field == "subclass") and itemSubType or itemType
            if value then
                group.names[value:lower()] = true
            else
                allCached = false
            end
        end
    end
    resolved = allCached
end

-- The protection group holding this item back, or nil if nothing does.
local function ProtectedBy(itemType, itemSubType, reqLevel)
    for _, group in ipairs(PROTECTIONS) do
        if cfg[group.option] then
            local value = (group.field == "subclass") and itemSubType or itemType
            if value and group.names[value:lower()] then
                -- A level-gated group only protects items that reach its level.
                local floor = group.minLevel and tonumber(cfg[group.minLevel])
                if not floor or (reqLevel or 0) >= floor then
                    return group
                end
            end
        end
    end
end

function handlers.MERCHANT_SHOW()
    if not cfg.autoSell then return end

    ResolveClassNames()          -- once per visit, not once per bag slot
    local wlIds, wlNames = BuildWhitelist()
    local count, total = 0, 0
    local kept, keptTotal = {}, 0

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local _, itemCount, locked = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if link and not locked then
                local name, _, quality, _, reqLevel, itemType, itemSubType,
                      _, _, _, sellPrice = GetItemInfo(link)
                local id = tonumber(link:match("item:(%d+)"))
                local whitelisted = (id and wlIds[id]) or (name and wlNames[name:lower()])
                local byQuality = quality and cfg.sellQuality[quality]
                -- Protections hold items back from the quality rules, but never
                -- from the whitelist: putting one there means "sell this anyway".
                local protection = not whitelisted and ProtectedBy(itemType, itemSubType, reqLevel)
                if byQuality and protection then
                    kept[protection.label] = (kept[protection.label] or 0) + 1
                    keptTotal = keptTotal + 1
                end
                -- Only ever sell items that actually have a vendor value.
                if (whitelisted or (byQuality and not protection)) and sellPrice and sellPrice > 0 then
                    total = total + sellPrice * (itemCount or 1)
                    count = count + 1
                    UseContainerItem(bag, slot)
                end
            end
        end
    end

    -- "2 trade goods, 1 elixir", in the order the protections are declared.
    local function KeptSummary()
        local parts = {}
        for _, group in ipairs(PROTECTIONS) do
            local n = kept[group.label]
            if n then
                parts[#parts + 1] = ("%d %s%s"):format(n, group.label, n == 1 and "" or "s")
            end
        end
        return table.concat(parts, ", ")
    end

    if count > 0 then
        local msg = ("Sold %d item%s for %s"):format(
            count, count == 1 and "" or "s", GetCoinTextureString(total))
        if keptTotal > 0 then
            msg = msg .. " |cff808080(kept " .. KeptSummary() .. ")|r"
        end
        ns.Print(msg)
    elseif keptTotal > 0 then
        ns.Print("Kept " .. KeptSummary() .. " that the quality rules would have sold.")
    end
end

-- ------------------------------------------------------------------ options UI
local QUALITIES = {
    { q = 0, label = "Poor (junk)" },
    { q = 1, label = "Common" },
    { q = 2, label = "Uncommon" },
    { q = 3, label = "Rare" },
    { q = 4, label = "Epic" },
}

local function ColoredQuality(q, text)
    local c = ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex .. text .. "|r" end
    return text
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Automation"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Automation")

    local BASE_X = 16
    local yPos = -48

    local function Header(text)
        local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X, yPos)
        fs:SetText("|cffffd100" .. text .. "|r")
        yPos = yPos - 22
        return fs
    end

    -- Returns the checkbox so callers can wire enable/disable of its children.
    local function AddCheck(label, tip, get, set, indent)
        local cb = ns.CreateCheck(panel, label, tip, get())
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X + (indent and 22 or 0), yPos)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
        end)
        yPos = yPos - (indent and 22 or 24)
        return cb
    end

    -- ---- Auto release ----
    Header("Auto release spirit")

    local relSubs = {}
    local function RefreshRelease()
        local on = cfg.autoRelease
        for _, cb in ipairs(relSubs) do
            cb.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
    end

    local relMaster = AddCheck("Auto release after death",
        "Automatically release your spirit when you die (in the zone types selected below). Waits briefly first and skips releasing if a resurrection is being offered or a soulstone is available.",
        function() return cfg.autoRelease end,
        function(v) cfg.autoRelease = v; RefreshRelease() end)

    relSubs[#relSubs + 1] = AddCheck("In battlegrounds",
        "Release automatically while in a battleground.",
        function() return cfg.releaseBG end,
        function(v) cfg.releaseBG = v end, true)
    relSubs[#relSubs + 1] = AddCheck("In the open world",
        "Release automatically when you die out in the world.",
        function() return cfg.releaseWorld end,
        function(v) cfg.releaseWorld = v end, true)
    relSubs[#relSubs + 1] = AddCheck("In dungeons / raids",
        "Release automatically in 5-man dungeons and raids. Off by default so you can wait for a battle-res.",
        function() return cfg.releaseDungeon end,
        function(v) cfg.releaseDungeon = v end, true)

    RefreshRelease()
    yPos = yPos - 6

    -- ---- Auto sell ----
    Header("Auto sell at vendors")

    local sellSubs = {}
    local function RefreshSell()
        local on = cfg.autoSell
        for _, cb in ipairs(sellSubs) do
            cb.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
    end

    AddCheck("Auto sell items when visiting a vendor",
        "When you open a merchant window, automatically sell items of the qualities selected below (plus anything on the whitelist). Only items with a vendor value are ever sold.",
        function() return cfg.autoSell end,
        function(v) cfg.autoSell = v; RefreshSell() end)

    for _, entry in ipairs(QUALITIES) do
        local q = entry.q
        sellSubs[#sellSubs + 1] = AddCheck(ColoredQuality(q, entry.label),
            "Auto-sell " .. entry.label:lower() .. " quality items.",
            function() return cfg.sellQuality[q] end,
            function(v) cfg.sellQuality[q] = v end, true)
    end

    sellSubs[#sellSubs + 1] = AddCheck("Never sell trade goods / crafting materials",
        "Skips anything the client classes as Trade Goods or a reagent -- ore, herbs, cloth, leather, enchanting mats, meat -- even when its quality is ticked above.\nThe always-sell whitelist still wins over this.",
        function() return cfg.protectTradeGoods end,
        function(v) cfg.protectTradeGoods = v end, true)

    sellSubs[#sellSubs + 1] = AddCheck("Never sell gemstones",
        "Skips gems and pearls -- Star Ruby, Small Lustrous Pearl, cut and uncut gems -- matched by item class, so the whole category is covered.",
        function() return cfg.protectGems end,
        function(v) cfg.protectGems = v end, true)

    local elixirCheck = AddCheck("Never sell elixirs from level",
        "Skips elixirs that require at least the level on the right, so low-level leftovers still get sold.\nFlasks and potions are separate categories and are not covered.",
        function() return cfg.protectElixirs end,
        function(v) cfg.protectElixirs = v end, true)
    sellSubs[#sellSubs + 1] = elixirCheck

    -- The level floor sits on the elixir row itself, after its label.
    local lvlBox = CreateFrame("EditBox", "HKSuiteElixirLevelBox", panel, "InputBoxTemplate")
    lvlBox:SetSize(66, 20)
    lvlBox:SetPoint("LEFT", elixirCheck.label, "RIGHT", 8, 0)
    lvlBox:SetAutoFocus(false)
    lvlBox:SetNumeric(true)
    lvlBox:SetText(tostring(cfg.elixirMinLevel or 30))

    local function SaveElixirLevel()
        local v = tonumber(lvlBox:GetText() or "") or 30
        if v < 1 then v = 1 elseif v > 255 then v = 255 end
        cfg.elixirMinLevel = v
        lvlBox:SetText(tostring(v))
    end

    lvlBox:SetScript("OnEnterPressed", function(self) SaveElixirLevel(); self:ClearFocus() end)
    lvlBox:SetScript("OnEditFocusLost", SaveElixirLevel)
    lvlBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(cfg.elixirMinLevel or 30)); self:ClearFocus()
    end)
    ns.CreateInlineAccept(lvlBox, SaveElixirLevel)

    RefreshSell()
    yPos = yPos - 6

    -- Whitelist editor.
    local wlLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    wlLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X, yPos)
    wlLabel:SetText("Always-sell whitelist (one item name or ID per line):")
    yPos = yPos - 18

    local wlScroll = CreateFrame("ScrollFrame", "HKSuiteAutoSellScroll", panel, "UIPanelScrollFrameTemplate")
    wlScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X + 4, yPos)
    wlScroll:SetSize(360, 90)
    wlScroll:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    wlScroll:SetBackdropColor(0, 0, 0, 0.4)

    local wlEdit = CreateFrame("EditBox", "HKSuiteAutoSellEdit", wlScroll)
    wlEdit:SetMultiLine(true)
    wlEdit:SetFontObject(ChatFontNormal)
    wlEdit:SetWidth(340)
    wlEdit:SetAutoFocus(false)
    wlEdit:SetTextInsets(4, 4, 4, 4)
    wlEdit:SetText(table.concat(cfg.whitelist, "\n"))
    local function SaveWhitelist(text)
        wipe(cfg.whitelist)
        for line in text:gmatch("[^\r\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then cfg.whitelist[#cfg.whitelist + 1] = line end
        end
    end
    wlEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    wlEdit:SetScript("OnEditFocusLost", function(self) SaveWhitelist(self:GetText()) end)
    wlScroll:SetScrollChild(wlEdit)

    -- The check in the box's corner commits without clicking away from it first.
    local wlSaved = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

    ns.CreateInlineAccept(wlEdit, function()
        SaveWhitelist(wlEdit:GetText())
        wlSaved:SetText("Saved: |cff00ff00" .. #cfg.whitelist .. "|r entr" .. (#cfg.whitelist == 1 and "y" or "ies"))
    end, wlScroll, "TOPRIGHT", -6, -6)

    wlSaved:SetPoint("TOPLEFT", wlScroll, "BOTTOMLEFT", 0, -8)
    wlSaved:SetText("Saved: |cff00ff00" .. #cfg.whitelist .. "|r entr" .. (#cfg.whitelist == 1 and "y" or "ies"))

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("automation")

    local frame = CreateFrame("Frame")
    for event in pairs(handlers) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if ns.IsModuleEnabled("automation") then
            handlers[event](...)
        end
    end)

    BuildOptionsPanel()
end
