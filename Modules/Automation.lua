local ADDON, ns = ...

-- =============================================================================
-- Automation module: hands-off conveniences.
--   * Auto release spirit after death (per zone type: BG / world / dungeon).
--   * Auto sell junk (and optionally other qualities) at vendors, holding back
--     protected categories and anything on the never-sell list, and optionally
--     collecting an item's transmog appearance before it goes.
--   * Auto repair at vendors, from guild funds when they're available.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "automation",
    title = "Automation",
    desc  = "Auto-release after death, auto-sell junk and auto-repair at vendors.",
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
    -- Protections: things the quality rules above are not allowed to sell.
    protectRealmBound = true,  -- anything the tooltip marks as realm bound
    protectWorldforged = true, -- anything the tooltip marks as worldforged
    protectTradeGoods = true,  -- crafting materials (ore, herbs, cloth, leather, mats)
    -- ...except these sub-categories, which are sold anyway when ticked.
    sellCloth      = false,
    sellLeather    = false,
    sellMetal      = false,
    sellHerbs      = false,
    sellMeat       = false,
    sellEnchanting = false,
    sellElemental  = false,
    protectGems       = true,  -- gemstones and pearls
    protectElixirs    = true,  -- elixirs from elixirMinLevel upwards
    elixirMinLevel    = 30,    -- required level an elixir must reach to be protected

    -- Learn an item's transmog appearance before the vendor takes it. Only ever
    -- applies to items the filter above already decided to sell.
    collectAppearances = false,

    -- Auto repair
    autoRepair       = false,  -- repair everything at vendors that can repair
    repairGuildFunds = true,   -- try the guild bank's repair allowance first

    neverSell   = {},          -- item names or IDs to never sell, whatever the quality rules say
}

local cfg  -- filled in OnInit

local After = ns.After

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
-- Build fast lookups from the never-sell list (numeric entries -> item IDs,
-- everything else -> lowercased item names).
local function BuildNeverSellList()
    local ids, names = {}, {}
    for _, entry in ipairs(cfg.neverSell) do
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
-- Everything the quality rules aren't allowed to sell, in the order they're
-- tested. Most groups match on the item's class (or sub-class) rather than on a
-- name list, so one entry covers a whole category: every profession's materials
-- live under Trade Goods, every gemstone under the gem class, every elixir under
-- the Elixir sub-class.
--
-- GetItemInfo gives only the *localized* class names on this client (3.3.5
-- returns no numeric class id), so instead of hardcoding "Trade Goods" each
-- group learns its names from reference items -- real items known to be in the
-- category. The English names seed each set so a group still works before the
-- client has cached its references.
--
-- Two things aren't item classes at all: bind state, which only exists on the
-- tooltip (`phrases`), and the player's own never-sell list (`listed`). Both are
-- protections like any other, so they show up in the same "kept" summary.
local PROTECTIONS = {
    {
        key    = "list",
        label  = "listed item",
        listed = true,
    },
    {
        key     = "realmbound",
        option  = "protectRealmBound",
        label   = "realm bound item",
        phrases = { "realm bound", "realmbound", "realm-bound" },
    },
    {
        key     = "worldforged",
        option  = "protectWorldforged",
        label   = "worldforged item",
        phrases = { "worldforged", "world forged", "world-forged" },
    },
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
        -- Sub-categories the player can let through anyway: keeping every
        -- material is the safe default, but nobody wants a bag of meat. Each one
        -- learns its localized sub-class name from a reference item, exactly the
        -- way the parent group learns its class name.
        exceptions = {
            { option = "sellCloth",      label = "Cloth",         field = "subclass", names = { ["cloth"] = true },         refs = { 2589 } },
            { option = "sellLeather",    label = "Leather",       field = "subclass", names = { ["leather"] = true },       refs = { 2318 } },
            { option = "sellMetal",      label = "Metal & stone", field = "subclass", names = { ["metal & stone"] = true }, refs = { 2770 } },
            { option = "sellHerbs",      label = "Herbs",         field = "subclass", names = { ["herb"] = true },          refs = { 2447 } },
            { option = "sellMeat",       label = "Meat",          field = "subclass", names = { ["meat"] = true },          refs = { 2672 } },
            { option = "sellEnchanting", label = "Enchanting",    field = "subclass", names = { ["enchanting"] = true },    refs = { 10940 } },
            { option = "sellElemental",  label = "Elemental",     field = "subclass", names = { ["elemental"] = true },     refs = { 7067 } },
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

-- Learn a group's class (or sub-class) names from its reference items. Returns
-- false while the client still has one of them uncached.
local function LearnNames(group)
    local allCached = true
    for _, id in ipairs(group.refs or {}) do
        local _, _, _, _, _, itemType, itemSubType = GetItemInfo(id)
        local value = (group.field == "subclass") and itemSubType or itemType
        if value then
            group.names[value:lower()] = true
        else
            allCached = false
        end
    end
    return allCached
end

-- Retried on later vendor visits until every reference has been cached.
local function ResolveClassNames()
    if resolved then return end
    local allCached = true
    for _, group in ipairs(PROTECTIONS) do
        if not LearnNames(group) then allCached = false end
        for _, exception in ipairs(group.exceptions or {}) do
            if not LearnNames(exception) then allCached = false end
        end
    end
    resolved = allCached
end

-- Bind state and Ascension's item modifiers only exist on the tooltip, so read
-- them off the bag item directly. More than one group asks about the same item, so
-- each slot's tooltip is built once per sell plan and kept as one lowercased blob.
local scanTip = CreateFrame("GameTooltip", "HKSuiteAutoSellScanTip", nil, "GameTooltipTemplate")
local scanCache = {}

local function TooltipText(bag, slot)
    local key = bag .. ":" .. slot
    local cached = scanCache[key]
    if cached then return cached end

    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    local lines = {}
    for i = 1, scanTip:NumLines() do
        local line = _G["HKSuiteAutoSellScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text then lines[#lines + 1] = text:lower() end
    end

    cached = table.concat(lines, "\n")
    scanCache[key] = cached
    return cached
end

local function TooltipHasPhrase(bag, slot, phrases)
    local text = TooltipText(bag, slot)
    for _, phrase in ipairs(phrases) do
        if text:find(phrase, 1, true) then return true end
    end
end

-- A sub-category the player has ticked to sell anyway, so the group that would
-- otherwise cover it lets this item past.
local function AllowedException(group, subType)
    if not (group.exceptions and subType) then return false end
    subType = subType:lower()
    for _, exception in ipairs(group.exceptions) do
        if cfg[exception.option] and exception.names[subType] then return true end
    end
    return false
end

-- The protection group holding this item back, or nil if nothing does. `item`
-- carries what each kind of group needs: where it sits in the bags, what the
-- client says it is, and whether the player listed it by name or id.
local function ProtectedBy(item)
    for _, group in ipairs(PROTECTIONS) do
        -- A group without an option (the never-sell list) is always on.
        if group.option == nil or cfg[group.option] then
            if group.listed then
                if item.listed then return group end
            elseif group.phrases then
                if item.bag and TooltipHasPhrase(item.bag, item.slot, group.phrases) then
                    return group
                end
            else
                local value = (group.field == "subclass") and item.subType or item.itemType
                if value and group.names[value:lower()]
                    and not AllowedException(group, item.subType) then
                    -- A level-gated group only protects items that reach its level.
                    local floor = group.minLevel and tonumber(cfg[group.minLevel])
                    if not floor or (item.reqLevel or 0) >= floor then
                        return group
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------- appearance collection
-- Ascension unlocks transmog appearances per item, and selling an item takes its
-- appearance with it. So before the vendor gets an item the filter picked out,
-- learn the appearance if it's still missing. Items the filter would *not* sell
-- are never touched -- no collecting, no selling.
--
-- Collecting is a server round-trip (CMSG_COLLECT_ITEM_APPEARANCE) and puts a
-- confirmation dialog up first, so items with an appearance to grab are handled
-- one at a time: collect, confirm, wait for the collection to register, sell.
local COLLECT_TIMEOUT = 2.5    -- seconds to give the server before moving on
local COLLECT_POLL    = 0.15   -- how often to look for the dialog / the result

local function AppearanceAPI()
    return C_Appearance and C_Appearance.GetItemAppearanceID
        and C_AppearanceCollection and C_AppearanceCollection.IsAppearanceCollected
        and C_AppearanceCollection.CollectItemAppearance and true or false
end

local function IsCollected(appearanceID)
    local ok, collected = pcall(C_AppearanceCollection.IsAppearanceCollected, appearanceID)
    return ok and collected and true or false
end

-- The appearance this item would teach us, or nil when it has none or we already
-- own it. Every call is guarded: these are custom APIs and the module has to keep
-- selling on a client that doesn't have them.
local function UncollectedAppearance(itemID)
    if not (itemID and cfg.collectAppearances and AppearanceAPI()) then return end
    if C_Appearance.IsTransmogable then
        local ok, transmogable = pcall(C_Appearance.IsTransmogable, itemID)
        if ok and not transmogable then return end
    end
    local ok, appearanceID = pcall(C_Appearance.GetItemAppearanceID, itemID)
    if not (ok and appearanceID) then return end
    if IsCollected(appearanceID) then return end
    return appearanceID
end

-- CollectItemAppearance is undocumented -- it isn't in the client's API docs and
-- carries no usage string. What gave it away is the dialog the game itself raises
-- on a Ctrl+Alt+left-click: CONFIRM_COLLECT_APPEARANCE is handed an *item GUID*
-- string, which its OnAccept passes straight through. So that's the call, and
-- GetContainerItemGUID is where a bag slot's GUID comes from. Note that a wrong
-- argument is ignored in silence -- no error, no packet -- so there's no point
-- guessing at it.
local COLLECT_DIALOG = "CONFIRM_COLLECT_APPEARANCE"

local function SendCollect(entry)
    if type(GetContainerItemGUID) ~= "function" then return false end
    local guid = GetContainerItemGUID(entry.bag, entry.slot)
    if not guid then return false end
    return pcall(C_AppearanceCollection.CollectItemAppearance, guid)
end

-- Calling the API directly doesn't normally raise the dialog, but accept it if
-- something does -- and only when it's actually about an appearance, since a
-- vendor visit can raise others.
local function AcceptAppearancePopup()
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local dialog = _G["StaticPopup" .. i]
        if dialog and dialog:IsShown() then
            local which = dialog.which or ""
            local label = _G["StaticPopup" .. i .. "Text"]
            local text  = label and label:GetText() or ""
            if which == COLLECT_DIALOG
                or which:upper():find("APPEARANCE", 1, true)
                or text:lower():find("appearance", 1, true) then
                local button = _G["StaticPopup" .. i .. "Button1"]
                local usable = button and button:IsShown() and button:IsEnabled()
                if usable and usable ~= 0 then
                    button:Click()
                    return true
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ auto sell
local run   -- the vendor visit in progress, nil when idle

local function AtVendor()
    return MerchantFrame and MerchantFrame:IsShown()
end

-- ----------------------------------------------------------------- auto repair
-- Repairs on the way out of the sell run, so anything the vendor just bought is
-- already paying for it. Guild funds are tried first when the guild allows it and
-- the allowance covers the bill (-1 is the unlimited allowance).
local repaired   -- already repaired at this merchant

local function GuildRepair(cost)
    if not cfg.repairGuildFunds then return false end
    if not (CanGuildBankRepair and CanGuildBankRepair()) then return false end
    local allowance = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
    if allowance ~= -1 and allowance < cost then return false end

    RepairAllItems(1)
    -- Nothing reports back whether the guild actually paid, so ask the vendor
    -- again: a bill that is gone was settled.
    local remaining = GetRepairAllCost()
    return not remaining or remaining <= 0
end

local function AutoRepair()
    if repaired or not cfg.autoRepair then return end
    if not (CanMerchantRepair and CanMerchantRepair()) then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    repaired = true

    if GuildRepair(cost) then
        ns.Print(("Repaired for %s from guild funds."):format(GetCoinTextureString(cost)))
        return
    end

    if GetMoney() < cost then
        ns.Print(("Not enough money to repair -- %s needed."):format(GetCoinTextureString(cost)))
        return
    end

    RepairAllItems()
    ns.Print(("Repaired for %s."):format(GetCoinTextureString(cost)))
end

-- "2 trade goods, 1 elixir", in the order the protections are declared.
local function KeptSummary(kept)
    local parts = {}
    for _, group in ipairs(PROTECTIONS) do
        local n = kept[group.label]
        if n then
            parts[#parts + 1] = ("%d %s%s"):format(n, group.label, n == 1 and "" or "s")
        end
    end
    return table.concat(parts, ", ")
end

local function FinishRun()
    if not run then return end
    local r = run
    run = nil

    if r.sold > 0 then
        local msg = ("Sold %d item%s for %s"):format(
            r.sold, r.sold == 1 and "" or "s", GetCoinTextureString(r.total))
        if r.collected > 0 then
            msg = msg .. (" |cff808080(collected %d appearance%s first)|r"):format(
                r.collected, r.collected == 1 and "" or "s")
        end
        if r.keptTotal > 0 then
            msg = msg .. " |cff808080(kept " .. KeptSummary(r.kept) .. ")|r"
        end
        ns.Print(msg)
    elseif r.keptTotal > 0 then
        ns.Print("Kept " .. KeptSummary(r.kept) .. " that the quality rules would have sold.")
    end

    -- Held back rather than sold: losing an uncollected appearance to a vendor is
    -- worse than leaving the item in the bag, so say so plainly.
    if r.uncollected > 0 then
        ns.Print(("Left %d item%s unsold: their appearance could not be collected."):format(
            r.uncollected, r.uncollected == 1 and "" or "s"))
    end

    if AtVendor() then AutoRepair() end
end

-- Everything the filter picked out, in bag order.
local function BuildSellPlan()
    ResolveClassNames()          -- once per visit, not once per bag slot
    wipe(scanCache)              -- bags may have moved since the last visit
    local listIds, listNames = BuildNeverSellList()
    local items, kept, keptTotal = {}, {}, 0

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local _, itemCount, locked = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if link and not locked then
                local name, _, quality, _, reqLevel, itemType, itemSubType,
                      _, _, _, sellPrice = GetItemInfo(link)
                local id = tonumber(link:match("item:(%d+)"))
                local byQuality = quality and cfg.sellQuality[quality]
                local protection = ProtectedBy({
                    bag = bag, slot = slot, itemType = itemType, subType = itemSubType,
                    reqLevel = reqLevel,
                    listed = (id and listIds[id]) or (name and listNames[name:lower()]),
                })
                if byQuality and protection then
                    kept[protection.label] = (kept[protection.label] or 0) + 1
                    keptTotal = keptTotal + 1
                end
                -- Only ever sell items that actually have a vendor value.
                if byQuality and not protection and sellPrice and sellPrice > 0 then
                    items[#items + 1] = {
                        bag = bag, slot = slot, link = link, id = id,
                        value = sellPrice * (itemCount or 1),
                    }
                end
            end
        end
    end
    return items, kept, keptTotal
end

local function SellEntry(entry)
    -- The plan was built before any of this ran; make sure the slot still holds
    -- the item we decided on.
    if GetContainerItemLink(entry.bag, entry.slot) ~= entry.link then return end
    run.sold  = run.sold + 1
    run.total = run.total + entry.value
    UseContainerItem(entry.bag, entry.slot)
end

local ProcessNext   -- forward declaration (the collect watcher calls back into it)

-- Poll while a collect is in flight and move on as soon as it registers. The poll
-- holds on to its own wait record, so a tick left over from an abandoned vendor
-- visit recognises that it is stale and stops.
local function WatchCollect(wait)
    if not run or run.waiting ~= wait then return end

    AcceptAppearancePopup()

    if wait.collected or IsCollected(wait.appearance) then
        run.waiting = nil
        run.collected = run.collected + 1
        SellEntry(wait.entry)
        return ProcessNext()
    end

    if not AtVendor() then
        run.waiting = nil
        return FinishRun()
    end

    if GetTime() - wait.started < COLLECT_TIMEOUT then
        return After(COLLECT_POLL, function() WatchCollect(wait) end)
    end

    run.waiting = nil
    run.uncollected = run.uncollected + 1   -- left in the bag, deliberately unsold
    return ProcessNext()
end

local function StartCollect(entry, appearanceID)
    local wait = { entry = entry, appearance = appearanceID, started = GetTime() }
    run.waiting = wait
    if not SendCollect(entry) then
        run.waiting = nil
        run.uncollected = run.uncollected + 1
        return ProcessNext()
    end
    After(COLLECT_POLL, function() WatchCollect(wait) end)
end

function ProcessNext()
    if not run then return end
    if not AtVendor() then return FinishRun() end

    run.index = run.index + 1
    local entry = run.items[run.index]
    if not entry then return FinishRun() end

    local appearanceID = entry.id and UncollectedAppearance(entry.id)
    if not appearanceID then
        SellEntry(entry)
        return ProcessNext()
    end
    return StartCollect(entry, appearanceID)
end

function handlers.MERCHANT_SHOW()
    FinishRun()   -- close off a previous visit that never saw its MERCHANT_CLOSED
    repaired = false

    -- Selling comes first so the repair bill can be paid out of the proceeds. With
    -- nothing to sell the run ends immediately and repairing follows straight on.
    if not cfg.autoSell then
        AutoRepair()
        return
    end

    local items, kept, keptTotal = BuildSellPlan()
    run = {
        items = items, kept = kept, keptTotal = keptTotal,
        index = 0, sold = 0, total = 0, collected = 0, uncollected = 0,
    }
    ProcessNext()
end

function handlers.MERCHANT_CLOSED()
    FinishRun()
end

-- The client's own answer to a collect request: settles the wait without holding
-- on for the collection cache to catch up.
function handlers.APPEARANCE_COLLECTED()
    if run and run.waiting then run.waiting.collected = true end
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

function M:BuildSettings(page)
    local function Check(label, tip, get, set, indent, onChange)
        return page:Check({
            label = label, tooltip = tip, indent = indent,
            get = get, set = set, onChange = onChange,
        })
    end

    -- ---- Auto release ----
    page:Header("Auto release spirit")

    local release = Check("Auto release after death",
        "Automatically release your spirit when you die (in the zone types selected below). Waits briefly first and skips releasing if a resurrection is being offered or a soulstone is available.",
        function() return cfg.autoRelease end,
        function(v) cfg.autoRelease = v end)

    release:BindChildren({
        Check("In battlegrounds", "Release automatically while in a battleground.",
            function() return cfg.releaseBG end,
            function(v) cfg.releaseBG = v end, true),
        Check("In the open world", "Release automatically when you die out in the world.",
            function() return cfg.releaseWorld end,
            function(v) cfg.releaseWorld = v end, true),
        Check("In dungeons / raids",
            "Release automatically in 5-man dungeons and raids. Off by default so you can wait for a battle-res.",
            function() return cfg.releaseDungeon end,
            function(v) cfg.releaseDungeon = v end, true),
    })

    -- ---- Auto sell ----
    page:Section({
        title = "Auto sell at vendors",
        tooltip = "When you open a merchant window, automatically sell items of the qualities selected below, minus anything a rule below or the never-sell list holds back. Only items with a vendor value are ever sold.",
        get = function() return cfg.autoSell end,
        set = function(v) cfg.autoSell = v end,
    })

    -- The section's own switch dims everything it holds, so none of these need
    -- collecting up for a BindChildren of their own.
    for _, entry in ipairs(QUALITIES) do
        local q = entry.q
        Check(ColoredQuality(q, entry.label),
            "Auto-sell " .. entry.label:lower() .. " quality items.",
            function() return cfg.sellQuality[q] end,
            function(v) cfg.sellQuality[q] = v end)
    end

    Check("Collect the appearance before selling",
        "Before an item goes to the vendor, check whether you have its transmog appearance and collect it first if you don't, confirming the dialog for you.\n\n"
        .. "Only ever applies to items the filter above already decided to sell -- nothing else is collected.\n\n"
        .. "An item whose appearance cannot be collected is left in your bags rather than sold.",
        function() return cfg.collectAppearances end,
        function(v) cfg.collectAppearances = v end)

    Check("Never sell realm bound items",
        "Skips anything whose tooltip says Realm Bound, even when its quality is ticked above.",
        function() return cfg.protectRealmBound end,
        function(v) cfg.protectRealmBound = v end)

    Check("Never sell worldforged items",
        "Skips anything whose tooltip says Worldforged, even when its quality is ticked above.",
        function() return cfg.protectWorldforged end,
        function(v) cfg.protectWorldforged = v end)

    local tradeGoods = Check("Never sell trade goods / crafting materials",
        "Skips anything the client classes as Trade Goods or a reagent -- ore, herbs, cloth, leather, enchanting mats, meat -- even when its quality is ticked above.",
        function() return cfg.protectTradeGoods end,
        function(v) cfg.protectTradeGoods = v end)

    page:Hint("…except these, which are sold anyway:", true)

    -- Laid out three to a row: as a plain indented list these seven would bury
    -- the rules underneath them.
    local TRADE_GOODS = {
        { option = "sellCloth",      label = "Cloth" },
        { option = "sellLeather",    label = "Leather" },
        { option = "sellMetal",      label = "Metal & stone" },
        { option = "sellHerbs",      label = "Herbs" },
        { option = "sellMeat",       label = "Meat" },
        { option = "sellEnchanting", label = "Enchanting" },
        { option = "sellElemental",  label = "Elemental" },
    }
    local tradeSubs = {}
    for i = 1, #TRADE_GOODS, 3 do
        local items = {}
        for j = i, math.min(i + 2, #TRADE_GOODS) do
            local option = TRADE_GOODS[j].option
            items[#items + 1] = {
                kind = "check", label = TRADE_GOODS[j].label, width = 165,
                get = function() return cfg[option] end,
                set = function(v) cfg[option] = v end,
            }
        end
        for _, widget in ipairs(page:Row(items, { indent = true, gap = 2 })) do
            tradeSubs[#tradeSubs + 1] = widget
        end
    end
    tradeGoods:BindChildren(tradeSubs)

    Check("Never sell gemstones",
        "Skips gems and pearls -- Star Ruby, Small Lustrous Pearl, cut and uncut gems -- matched by item class, so the whole category is covered.",
        function() return cfg.protectGems end,
        function(v) cfg.protectGems = v end)

    Check("Never sell elixirs",
        "Skips elixirs that require at least the level below, so low-level leftovers still get sold.\nFlasks and potions are separate categories and are not covered.",
        function() return cfg.protectElixirs end,
        function(v) cfg.protectElixirs = v end)

    page:Input({
        label = "…from required level", indent = true, width = 80,
        name = "HKSuiteElixirLevelBox",
        numeric = true, min = 1, max = 255, step = 1,
        get = function() return cfg.elixirMinLevel or 30 end,
        set = function(v) cfg.elixirMinLevel = v end,
    })

    -- ---- Auto repair ----
    page:Section({
        title = "Auto repair at vendors",
        tooltip = "When you open a merchant that can repair, repairs all your gear. Runs after auto-sell, so anything the vendor just bought helps pay for it.",
        get = function() return cfg.autoRepair end,
        set = function(v) cfg.autoRepair = v end,
    })

    Check("Use guild funds when available",
        "Pays from the guild bank's repair allowance when your rank has one and it covers the bill; otherwise your own money is used.",
        function() return cfg.repairGuildFunds end,
        function(v) cfg.repairGuildFunds = v end)

    -- ---- Never-sell list ----
    page:Section({ title = "Never-sell list" })
    local saved
    local function SavedText()
        return "Saved: |cff00ff00" .. #cfg.neverSell .. "|r entr"
            .. (#cfg.neverSell == 1 and "y" or "ies")
    end

    local list = page:TextArea({
        label = "One item name or ID per line. These are kept whatever the settings above say.",
        name = "HKSuiteNeverSellEdit", height = 110,
        get = function() return table.concat(cfg.neverSell, "\n") end,
        set = function(text)
            wipe(cfg.neverSell)
            for line in text:gmatch("[^\r\n]+") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" then cfg.neverSell[#cfg.neverSell + 1] = line end
            end
        end,
        onChange = function() if saved then saved:SetText(SavedText()) end end,
    })

    saved = page:Hint(SavedText())
    page:Hint("Click into the box, then shift-click an item in your bags to add it by name.")

    -- Shift-clicking an item hands its link to ChatEdit_InsertLink. This box isn't
    -- a chat edit box, so nothing lands in it on its own -- catch the link and
    -- append the item's name rather than making the player type it out. Focus is
    -- what marks the intent: without it, linking an item in chat would add it.
    local function AddListedItem(link)
        local name = tostring(link):match("%[(.-)%]")
        if not name or name == "" then return end

        list:Commit()   -- fold in anything typed but not yet saved
        for _, entry in ipairs(cfg.neverSell) do
            if entry:lower() == name:lower() then
                ns.Print(name .. " is already on the never-sell list.")
                return
            end
        end

        cfg.neverSell[#cfg.neverSell + 1] = name
        list:Refresh()
        saved:SetText(SavedText())
        ns.Print("Never-sell list: added " .. name .. ".")
    end

    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and list.edit:HasFocus() then AddListedItem(link) end
    end)

    page:OnRefresh(function() saved:SetText(SavedText()) end)
end

function M:OnInit()
    cfg = ns.GetConfig("automation")

    local frame = CreateFrame("Frame")
    for event in pairs(handlers) do
        -- Some of these are Ascension's own events; registering one a client
        -- doesn't have raises, and must not take the rest down with it.
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if ns.IsModuleEnabled("automation") then
            handlers[event](...)
        end
    end)

end
