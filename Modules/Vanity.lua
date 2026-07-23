local ADDON, ns = ...

-- =============================================================================
-- Vanity module: automatically delivers unlearned vanity-collection spells you
-- already own. Ported from XanAscTweaks (VanityGrab) — uses Ascension's custom
-- VANITY_ITEMS / C_VanityCollection APIs.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "vanity",
    title = "Auto-Grab Vanity",
    desc  = "Delivers unlearned vanity spells you own (on login and on demand).",
})

ns.defaults.vanity = {
    grabOnLogin = true,
}

local cfg
local grablist = {}
local ticker

local function apiReady()
    return VANITY_ITEMS and C_VanityCollection and C_VanityCollection.IsCollectionItemOwned
        and RequestDeliverVanityCollectionItem
end

-- Items currently in the player's bags, keyed by itemID.
local function heldItems()
    local ret = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, id = link:find("^|c%x+|Hitem:(%d+):.+")
                if id then ret[tonumber(id)] = true end
            end
        end
    end
    return ret
end

-- Manastorm consumables come in ranks; we only want the highest owned rank, and
-- only when Manastorm is enabled.
local MANASTORM_ITEMS = {
    ["Chakra Chug"] = true, ["Cleanse"] = true, ["Curing"] = true,
    ["Frogduck Morph Machine"] = true, ["Genius Juice"] = true,
    ["Harm Repellant Remedy"] = true, ["Incantation Intensifier"] = true,
    ["Interrupt Rod"] = true, ["Long Haul Liquid"] = true,
    ["Manastorm Cleanse"] = true, ["Manastorm Curing"] = true,
    ["Manastorm Purification"] = true, ["Millhouse Mobility Mixture"] = true,
    ["Motion Lotion"] = true, ["Muscle Maxer"] = true, ["Purification"] = true,
    ["Purge-O-Matic"] = true, ["Rage Rush Solution"] = true,
    ["Reflex Booster"] = true, ["Sprint Serum"] = true,
    ["Taunting Tonic"] = true, ["Tiny Ticking Time-Bomb"] = true,
    ["Hearty Heal Upgrade"] = true,
}

local function manastormEnabled()
    return not (C_Config and C_Config.GetBoolConfig) or C_Config.GetBoolConfig("CONFIG_MANASTORM_ENABLED")
end

local function isManastorm(v)
    if MANASTORM_ITEMS[v.name] then
        return v.name, 1, IsSpellKnown(v.learnedSpell) or not manastormEnabled()
    end
    local name, rank = v.name:match("(.-) %(Rank (.-)%)")
    if name and MANASTORM_ITEMS[name] then
        return name, tonumber(rank), IsSpellKnown(v.learnedSpell) or not manastormEnabled()
    end
end

-- Deliver one queued item; called on a timer so we don't spam the server.
local function getVanity()
    local id = table.remove(grablist)
    if not id then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    if not CheckKnownItem or CheckKnownItem(id) then
        RequestDeliverVanityCollectionItem(id)
    end
    local info = VANITY_ITEMS[id]
    ns.Print("Grabbing " .. (info and info.name or tostring(id)) .. " (" .. id .. "). " .. #grablist .. " remaining.")
    if #grablist <= 0 and ticker then ticker:Cancel() ticker = nil end
end

function ns.GrabVanity()
    if not ns.IsModuleEnabled("vanity") then return end
    if not apiReady() then
        ns.Print("Vanity collection API not available on this client.")
        return
    end

    grablist = {}
    local known_spells = {}
    local held = heldItems()
    for i = 1, GetNumCompanions("CRITTER") do
        local _, _, sID = GetCompanionInfo("CRITTER", i)
        known_spells[sID] = true
    end
    for i = 1, GetNumCompanions("MOUNT") do
        local _, _, sID = GetCompanionInfo("MOUNT", i)
        known_spells[sID] = true
    end

    -- Items that hand over an unusable item instead of teaching the spell.
    local badItems = {
        All = {
            [222739] = true, [3001007] = true, [3001008] = true, [1030180] = true,
            [79315] = true, [101170] = true, [79316] = true,
        },
        Alliance = {},
        Horde = {},
    }
    -- Bundles whose vanity unlocks in the wardrobe but doesn't teach the spell.
    local nestedSpell = {
        [571959] = 902229, -- Stargazer's Blessing
        [499428] = 499587, -- Raid Marker - Bundle
    }

    local mCache, mmm, max_mmm, known_mmm = {}, {}, 0, 0
    local faction = UnitFactionGroup("player") or "Alliance"

    for k, v in pairs(VANITY_ITEMS) do
        if C_VanityCollection.IsCollectionItemOwned(k) then
            if v.learnedSpell > 1 then
                local name, rank, known = isManastorm(v)
                if name then
                    if not mCache[name] or mCache[name].rank < rank then
                        mCache[name] = { rank = rank, known = known, id = k, itemid = v.itemid }
                    end
                elseif v.name:find("Millhouse Mobility Mixture %(Upgrade") then
                    if manastormEnabled() then
                        local r = tonumber(v.name:match("Millhouse Mobility Mixture %(Upgrade Rank (%d+)"))
                        if r then
                            if r > max_mmm then max_mmm = r end
                            if IsSpellKnown(v.learnedSpell) and r > known_mmm then known_mmm = r end
                            mmm[r] = { id = k, itemid = v.itemid }
                        end
                    end
                elseif not (IsSpellKnown(v.learnedSpell) or known_spells[v.learnedSpell]) and not held[v.itemid] then
                    local isHeroTome = v.name:find("Tome of") and C_Player and not C_Player:IsHero()
                    if badItems.All[v.itemid] or (badItems[faction] and badItems[faction][v.itemid]) or isHeroTome then
                        -- skip: would give an unusable item
                    else
                        table.insert(grablist, k)
                    end
                end
            else
                if nestedSpell[v.itemid] and not held[v.itemid] and not IsSpellKnown(nestedSpell[v.itemid]) then
                    table.insert(grablist, k)
                end
            end
        end
    end

    for _, v in pairs(mCache) do
        if not v.known and not held[v.itemid] then table.insert(grablist, v.id) end
    end
    for i = known_mmm + 1, max_mmm do
        if mmm[i] and not held[mmm[i].itemid] then table.insert(grablist, mmm[i].id) end
    end

    if #grablist > 0 then
        ns.Print("Grabbing " .. #grablist .. " unlearned vanity spell(s).")
        if C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(2, getVanity)
        else
            while #grablist > 0 do getVanity() end
        end
    else
        ns.Print("No unlearned vanity spells to grab.")
    end
end

-- Grab a specific vanity item by name (e.g. a repeatable warchest), if owned.
function ns.GrabVanityByName(name)
    if not ns.IsModuleEnabled("vanity") then return end
    if not apiReady() then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    local id
    for k, v in pairs(VANITY_ITEMS) do
        if v.name == name then id = k break end
    end
    if not id then                                   -- fallback: substring match
        for k, v in pairs(VANITY_ITEMS) do
            if v.name:find(name, 1, true) then id = k break end
        end
    end
    if not id then ns.Print(name .. " not found in the vanity list.") return end
    if not C_VanityCollection.IsCollectionItemOwned(id) then
        ns.Print(name .. " is not in your collection.")
        return
    end
    RequestDeliverVanityCollectionItem(id)
    ns.Print("Grabbing " .. (VANITY_ITEMS[id].name or name) .. ".")
end

-- Grab a specific vanity item by its collection ID (most reliable), if owned.
function ns.GrabVanityById(id, label)
    if not ns.IsModuleEnabled("vanity") then return end
    if not (C_VanityCollection and C_VanityCollection.IsCollectionItemOwned and RequestDeliverVanityCollectionItem) then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    label = label or ("vanity " .. id)
    if not C_VanityCollection.IsCollectionItemOwned(id) then
        ns.Print(label .. " is not in your collection.")
        return
    end
    RequestDeliverVanityCollectionItem(id)
    ns.Print("Grabbing " .. label .. ".")
end

-- ---------------------------------------------------------------- bundle grab
-- Fixed vanity IDs. The collection's internal names don't match the item names,
-- so we grab by ID. Feather has two possible IDs; only one exists per collection.
local BUNDLE = {
    { id = 1777028, name = "Thermal Anvil" },
    { id = 1903512, name = "Gnomish Portable Post Tube" },
    { id = 1913517, name = "Portable Call Board (Outlaw)" },
    { id = 499428,  name = "Raid Marker - Bundle" },
    { id = 134985,  name = "Personal Bank" },
    { id = 1180097, name = "Realm Bank" },
    { id = 977025,  name = "Feather of Ancients: Azeroth", group = "feather" },
    { id = 134989,  name = "Feather of Ancients: Azeroth", group = "feather" },
    { id = 2903513, name = "Mechanical Mystic Altar" },
    { id = 203955,  name = "Altar of Ancient Kings" },
    { id = 8210202, name = "Altar of the Black Harvest" },
    { id = 8210199, name = "Altar of the Conclave" },
    { id = 8210195, name = "Altar of the Dreamweavers" },
    { id = 8210201, name = "Altar of the Maelstrom" },
    { id = 8210198, name = "Altar of the Silver Hand" },
    { id = 8210250, name = "Altar of the Tirisgarde" },
    { id = 203954,  name = "Altar of the Tirisgarde" },
    { id = 8210200, name = "Altar of the Uncrowned" },
    { id = 8210196, name = "Altar of the Unseen Path" },
    { id = 8210192, name = "Build Master's Mystic Enchanting Altar" },
    { id = 8210197, name = "Destined Mystic Enchanting Altar" },
    { id = 406,     name = "Felforged Enchanting Altar" },
    { id = 1903513, name = "Mystic Enchanting Altar" },
    { id = 503515,  name = "Scribe's Mystic Enchanting Altar" },
}
local BUNDLE_FACTION = {
    Alliance = {
        { id = 1913515, name = "Portable Call Board (Alliance)" },
        { id = 1175626, name = "Scroll of Retreat: Stormwind" },
    },
    Horde = {
        { id = 1913516, name = "Portable Call Board (Horde)" },
        { id = 1175627, name = "Scroll of Retreat: Orgrimmar" },
    },
}

local function ResolveBundle()
    local list = {}
    for _, e in ipairs(BUNDLE) do list[#list + 1] = e end
    local fac = BUNDLE_FACTION[UnitFactionGroup("player")]
    if fac then for _, e in ipairs(fac) do list[#list + 1] = e end end

    local seenId, missSeen, toGrab, missing = {}, {}, {}, {}
    local groupChosen, groupSeen, groupName = {}, {}, {}
    for _, e in ipairs(list) do
        if not seenId[e.id] then
            seenId[e.id] = true
            local owned = C_VanityCollection.IsCollectionItemOwned(e.id)
            if e.group then
                -- Grouped entries are alternatives: grab only the first owned one.
                groupSeen[e.group] = true
                groupName[e.group] = e.name
                if owned and not groupChosen[e.group] then
                    groupChosen[e.group] = true
                    toGrab[#toGrab + 1] = { id = e.id, name = e.name }
                end
            elseif owned then
                toGrab[#toGrab + 1] = { id = e.id, name = e.name }
            elseif not missSeen[e.name] then
                missSeen[e.name] = true
                missing[#missing + 1] = e.name
            end
        end
    end
    -- A group with nothing owned counts as one missing entry.
    for g in pairs(groupSeen) do
        if not groupChosen[g] then missing[#missing + 1] = groupName[g] end
    end
    return toGrab, missing
end

-- Deliver one at a time (the server only honours one delivery request at a time),
-- with a progress dialog.
local bundleQueue, bundleTicker = {}, nil
local bundleTotal, bundleDone = 0, 0
local bundleFrame

local function EnsureBundleFrame()
    if bundleFrame then return bundleFrame end
    local f = CreateFrame("Frame", "HKSuiteBundleProgress", UIParent)
    f:SetSize(360, 130)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("HKSuite — Grabbing Vanity Bundle")

    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.status:SetPoint("TOP", 0, -40)
    f.status:SetWidth(330); f.status:SetJustifyH("CENTER")

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24)
    cancel:SetPoint("BOTTOM", 0, 14)
    cancel:SetText("Cancel / Close")
    cancel:SetScript("OnClick", function()
        if bundleTicker then bundleTicker:Cancel() bundleTicker = nil end
        bundleQueue = {}
        f:Hide()
    end)

    bundleFrame = f
    return f
end

local function bundleStep()
    local e = table.remove(bundleQueue, 1)
    if not e then
        if bundleTicker then bundleTicker:Cancel() bundleTicker = nil end
        return
    end
    RequestDeliverVanityCollectionItem(e.id)
    bundleDone = bundleDone + 1
    if bundleFrame then
        bundleFrame.status:SetText(("Grabbing %d / %d:\n%s"):format(bundleDone, bundleTotal, e.name))
    end
    if #bundleQueue == 0 then
        if bundleTicker then bundleTicker:Cancel() bundleTicker = nil end
        if bundleFrame then bundleFrame.status:SetText(("Done — grabbed %d item(s)."):format(bundleDone)) end
    end
end

function ns.GrabVanityBundle()
    if not ns.IsModuleEnabled("vanity") then return end
    if not (C_VanityCollection and C_VanityCollection.IsCollectionItemOwned and RequestDeliverVanityCollectionItem) then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    local toGrab, missing = ResolveBundle()
    if #toGrab == 0 then ns.Print("No utility vanity items to grab.") return end

    if bundleTicker then bundleTicker:Cancel() bundleTicker = nil end
    bundleQueue, bundleTotal, bundleDone = toGrab, #toGrab, 0

    local f = EnsureBundleFrame()
    f:Show()
    f.status:SetText(("Grabbing %d item(s)…%s"):format(bundleTotal,
        #missing > 0 and ("\n(" .. #missing .. " not owned)") or ""))

    bundleStep()   -- first immediately, rest on a short interval
    if #bundleQueue > 0 then
        if C_Timer and C_Timer.NewTicker then
            bundleTicker = C_Timer.NewTicker(2, bundleStep)
        else
            while #bundleQueue > 0 do bundleStep() end
        end
    end
end

-- ------------------------------------------------- delete warchest duplicates
-- The consumable items the Fel Enchanted Warchest grants; once collected as
-- vanity, the physical copies are just clutter. Matched by name (never bags).
local DELETE_NAMES = {
    "Fel-Infused Tabard of Ascension",
    "Felflame Talbuk",
    "Fel-Infused Gateway",
    "Pit Lord's Eye",
}
local DELETE_SET = {}
for _, n in ipairs(DELETE_NAMES) do DELETE_SET[n:lower()] = true end

local function bagItemName(link)
    return link and link:match("|h%[(.+)%]|h")
end

local function CountFelItems()
    local c = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local n = bagItemName(GetContainerItemLink(bag, slot))
            if n and DELETE_SET[n:lower()] then c = c + 1 end
        end
    end
    return c
end

function ns.DoDeleteFelItems()
    local c = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local n = bagItemName(GetContainerItemLink(bag, slot))
            if n and DELETE_SET[n:lower()] then
                PickupContainerItem(bag, slot)
                DeleteCursorItem()
                c = c + 1
            end
        end
    end
    ns.Print("Deleted " .. c .. " Fel Warchest item(s).")
end

StaticPopupDialogs["HKSUITE_DELETE_FEL"] = {
    text = "Delete %d Fel Enchanted Warchest item(s) from your bags?\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.DoDeleteFelItems() end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

function ns.DeleteFelItems()
    if not ns.IsModuleEnabled("vanity") then return end
    local c = CountFelItems()
    if c == 0 then ns.Print("No Fel Warchest items found in your bags.") return end
    StaticPopup_Show("HKSUITE_DELETE_FEL", c)
end

-- ------------------------------------------------- delete vanity from bags
-- A bag item is a vanity item if its tooltip carries Ascension's
-- "You own this vanity item" line. (We deliberately do NOT match
-- "collected this appearance" — that's on every transmog-unlocked gear piece.)
local scanTip = CreateFrame("GameTooltip", "HKSuiteVanityScanTip", nil, "GameTooltipTemplate")

-- Owned vanity items that may be deleted even when NOT soulbound (by name).
local NO_BIND_REQUIRED = { ["realm bank"] = true }

local function isOwnedVanity(bag, slot)
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    local owned, bound = false, false
    for i = 1, scanTip:NumLines() do
        local fs = _G["HKSuiteVanityScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local t = text:lower()
            -- The full "you own" prefix excludes the negatives ("You don't own…").
            if t:find("you own this vanity item", 1, true) then owned = true end
            if t:find("soulbound", 1, true) then bound = true end
        end
    end
    if not owned then return false end
    if bound then return true end
    -- Not soulbound: only delete if it's on the no-bind-required whitelist.
    local link = GetContainerItemLink(bag, slot)
    local name = link and link:match("|h%[(.+)%]|h")
    return name ~= nil and NO_BIND_REQUIRED[name:lower()] == true
end

-- All owned vanity items in bags.
local function ScanCollected()
    local found = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and isOwnedVanity(bag, slot) then
                local id = tonumber(link:match("|Hitem:(%d+):"))
                found[#found + 1] = { bag = bag, slot = slot, id = id, name = bagItemName(link) or ("item:" .. tostring(id)) }
            end
        end
    end
    return found
end

-- Extra copies of the same vanity item in bags (keeps one of each).
local function ScanDuplicateCopies()
    local kept, found = {}, {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("|Hitem:(%d+):"))
            if id and isOwnedVanity(bag, slot) then
                if kept[id] then
                    found[#found + 1] = { bag = bag, slot = slot, id = id, name = bagItemName(link) or ("item:" .. id) }
                else
                    kept[id] = true   -- keep the first copy
                end
            end
        end
    end
    return found
end

local pending = {}

function ns.DoDeleteVanityPending()
    local c = 0
    for _, e in ipairs(pending) do
        local link = GetContainerItemLink(e.bag, e.slot)
        local id = link and tonumber(link:match("|Hitem:(%d+):"))
        if id == e.id then                       -- slot still holds the same item
            PickupContainerItem(e.bag, e.slot)
            DeleteCursorItem()
            c = c + 1
        end
    end
    pending = {}
    ns.Print("Deleted " .. c .. " vanity item(s).")
end

StaticPopupDialogs["HKSUITE_DELETE_VANITY"] = {
    text = "Delete %d vanity item(s) from your bags?\nSee chat for the list. This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.DoDeleteVanityPending() end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function PrepareDelete(found, label)
    pending = found
    if #pending == 0 then ns.Print("No " .. label .. " found in your bags.") return end
    local names = {}
    for i, e in ipairs(pending) do
        if i > 40 then names[#names + 1] = "…"; break end
        names[#names + 1] = e.name
    end
    ns.Print("Deleting " .. #pending .. " " .. label .. ": " .. table.concat(names, ", "))
    StaticPopup_Show("HKSUITE_DELETE_VANITY", #pending)
end

function ns.DeleteCollectedVanity()
    if not ns.IsModuleEnabled("vanity") then return end
    if not (VANITY_ITEMS and C_VanityCollection and C_VanityCollection.IsCollectionItemOwned) then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    PrepareDelete(ScanCollected(), "collected vanity items")
end

function ns.DeleteDuplicateVanity()
    if not ns.IsModuleEnabled("vanity") then return end
    if not VANITY_ITEMS then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    PrepareDelete(ScanDuplicateCopies(), "duplicate vanity items")
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Auto-Grab Vanity"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auto-Grab Vanity")

    local gl = ns.CreateCheck(panel, "Grab unlearned vanity on login",
        "Collects vanity spells you own but haven't learned yet.", cfg.grabOnLogin)
    gl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    gl:SetScript("OnClick", function(self) cfg.grabOnLogin = self:GetChecked() and true or false end)

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(210, 24)
    btn:SetText("Grab unlearned vanity")
    btn:SetPoint("TOPLEFT", gl, "BOTTOMLEFT", 0, -14)
    btn:SetScript("OnClick", ns.GrabVanity)

    -- Fel Warchest grab + its cleanup, side by side.
    local felBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    felBtn:SetSize(210, 24)
    felBtn:SetText("Grab Fel Enchanted Warchest")
    felBtn:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -8)
    felBtn:SetScript("OnClick", function() ns.GrabVanityById(657112, "Fel Enchanted Warchest") end)

    local delFelBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delFelBtn:SetSize(200, 24)
    delFelBtn:SetText("Delete Fel Warchest items")
    delFelBtn:SetPoint("LEFT", felBtn, "RIGHT", 8, 0)
    delFelBtn:SetScript("OnClick", ns.DeleteFelItems)

    local bundleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bundleBtn:SetSize(210, 24)
    bundleBtn:SetText("Grab utility bundle")
    bundleBtn:SetPoint("TOPLEFT", felBtn, "BOTTOMLEFT", 0, -8)
    bundleBtn:SetScript("OnClick", ns.GrabVanityBundle)

    local bundleHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    bundleHint:SetPoint("TOPLEFT", bundleBtn, "BOTTOMLEFT", 2, -6)
    bundleHint:SetWidth(360); bundleHint:SetJustifyH("LEFT")
    bundleHint:SetText("Collects your utility vanity items (anvils, call boards, altars, retreat scrolls, and more).")

    local collectedBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    collectedBtn:SetSize(210, 24)
    collectedBtn:SetText("Delete collected vanity items")
    collectedBtn:SetPoint("TOPLEFT", bundleHint, "BOTTOMLEFT", -2, -16)
    collectedBtn:SetScript("OnClick", ns.DeleteCollectedVanity)

    local collectedHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    collectedHint:SetPoint("TOPLEFT", collectedBtn, "BOTTOMLEFT", 2, -6)
    collectedHint:SetWidth(360); collectedHint:SetJustifyH("LEFT")
    collectedHint:SetText("Removes vanity items from your bags that you already own in your collection.")

    local dupBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    dupBtn:SetSize(210, 24)
    dupBtn:SetText("Delete duplicate vanity items")
    dupBtn:SetPoint("TOPLEFT", collectedHint, "BOTTOMLEFT", -2, -14)
    dupBtn:SetScript("OnClick", ns.DeleteDuplicateVanity)

    local dupHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dupHint:SetPoint("TOPLEFT", dupBtn, "BOTTOMLEFT", 2, -6)
    dupHint:SetWidth(360); dupHint:SetJustifyH("LEFT")
    dupHint:SetText("Removes extra copies of vanity items, keeping one of each.")

    InterfaceOptions_AddCategory(panel)
end

-- Diagnostic: inspect VANITY_ITEMS so we can resolve real names/IDs.
--   /hkvanity            -> entry count + field names
--   /hkvanity thermal    -> entries whose name/item-name contains "thermal"
SLASH_HKVANITY1 = "/hkvanity"
SlashCmdList["HKVANITY"] = function(msg)
    if not VANITY_ITEMS then ns.Print("VANITY_ITEMS is nil (not loaded).") return end
    local search = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local count, shown, sampled = 0, 0, false
    for k, v in pairs(VANITY_ITEMS) do
        count = count + 1
        if not sampled and type(v) == "table" then
            local fields = {}
            for fk in pairs(v) do fields[#fields + 1] = tostring(fk) end
            ns.Print("entry fields: " .. table.concat(fields, ", "))
            sampled = true
        end
        if search ~= "" and shown < 20 and type(v) == "table" then
            local nm = tostring(v.name or "")
            local iname = v.itemid and GetItemInfo(v.itemid) or nil
            if nm:lower():find(search, 1, true) or (iname and iname:lower():find(search, 1, true)) then
                ns.Print(k .. " | name='" .. nm .. "'" .. (iname and (" item='" .. iname .. "'") or ""))
                shown = shown + 1
            end
        end
    end
    ns.Print(("Total VANITY_ITEMS: %d%s"):format(count, search ~= "" and (", matches: " .. shown) or ""))
end

function M:OnInit()
    cfg = ns.GetConfig("vanity")
    BuildOptionsPanel()

    if cfg.grabOnLogin then
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_LOGIN")
        ev:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_LOGIN")
            if C_Timer and C_Timer.After then
                C_Timer.After(5, ns.GrabVanity)   -- let collection data load first
            else
                ns.GrabVanity()
            end
        end)
    end
end
