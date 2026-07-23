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
    { id = 977025,  name = "Feather of Ancients: Azeroth" },
    { id = 134989,  name = "Feather of Ancients: Azeroth" },
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
    for _, e in ipairs(list) do
        if not seenId[e.id] then
            seenId[e.id] = true
            if C_VanityCollection.IsCollectionItemOwned(e.id) then
                toGrab[#toGrab + 1] = { id = e.id, name = e.name }
            elseif not missSeen[e.name] then
                missSeen[e.name] = true
                missing[#missing + 1] = e.name
            end
        end
    end
    return toGrab, missing
end

function ns.GrabVanityBundle()
    if not ns.IsModuleEnabled("vanity") then return end
    if not (C_VanityCollection and C_VanityCollection.IsCollectionItemOwned and RequestDeliverVanityCollectionItem) then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    local toGrab, missing = ResolveBundle()
    if #toGrab == 0 then ns.Print("No utility vanity items to grab.") return end
    for _, e in ipairs(toGrab) do
        RequestDeliverVanityCollectionItem(e.id)
    end
    ns.Print("Grabbed " .. #toGrab .. " utility vanity item(s)" ..
        (#missing > 0 and (" (" .. #missing .. " not owned).") or "."))
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

-- ------------------------------------------------- delete duplicate vanity
-- A bag item is a "duplicate" if it's a vanity item whose collection entry you
-- already own (you can re-deliver it from your collection any time).
local function VanityItemMap()
    local map = {}
    if VANITY_ITEMS then
        for k, v in pairs(VANITY_ITEMS) do
            if v.itemid then map[v.itemid] = k end
        end
    end
    return map
end

local function ScanDuplicates()
    local map = VanityItemMap()
    local found = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("|Hitem:(%d+):"))
            local vanityID = id and map[id]
            if vanityID and C_VanityCollection.IsCollectionItemOwned(vanityID) then
                found[#found + 1] = { bag = bag, slot = slot, id = id, name = bagItemName(link) or ("item:" .. id) }
            end
        end
    end
    return found
end

local pendingDupes = {}

function ns.DoDeleteDuplicateVanity()
    local c = 0
    for _, e in ipairs(pendingDupes) do
        local link = GetContainerItemLink(e.bag, e.slot)
        local id = link and tonumber(link:match("|Hitem:(%d+):"))
        if id == e.id then                       -- slot still holds the same item
            PickupContainerItem(e.bag, e.slot)
            DeleteCursorItem()
            c = c + 1
        end
    end
    pendingDupes = {}
    ns.Print("Deleted " .. c .. " duplicate vanity item(s).")
end

StaticPopupDialogs["HKSUITE_DELETE_DUPES"] = {
    text = "Delete %d duplicate vanity item(s) from your bags?\nSee chat for the full list. This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.DoDeleteDuplicateVanity() end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

function ns.DeleteDuplicateVanity()
    if not ns.IsModuleEnabled("vanity") then return end
    if not (VANITY_ITEMS and C_VanityCollection and C_VanityCollection.IsCollectionItemOwned) then
        ns.Print("Vanity collection API not available on this client.")
        return
    end
    pendingDupes = ScanDuplicates()
    if #pendingDupes == 0 then ns.Print("No duplicate vanity items found in your bags.") return end

    local names = {}
    for i, e in ipairs(pendingDupes) do
        if i > 40 then names[#names + 1] = "…"; break end
        names[#names + 1] = e.name
    end
    ns.Print("Duplicate vanity items (" .. #pendingDupes .. "): " .. table.concat(names, ", "))
    StaticPopup_Show("HKSUITE_DELETE_DUPES", #pendingDupes)
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

    local felBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    felBtn:SetSize(210, 24)
    felBtn:SetText("Grab Fel Enchanted Warchest")
    felBtn:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -8)
    felBtn:SetScript("OnClick", function() ns.GrabVanityById(657112, "Fel Enchanted Warchest") end)

    local bundleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bundleBtn:SetSize(210, 24)
    bundleBtn:SetText("Grab utility bundle")
    bundleBtn:SetPoint("TOPLEFT", felBtn, "BOTTOMLEFT", 0, -8)
    bundleBtn:SetScript("OnClick", ns.GrabVanityBundle)

    local bundleHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    bundleHint:SetPoint("TOPLEFT", bundleBtn, "BOTTOMLEFT", 2, -6)
    bundleHint:SetWidth(360); bundleHint:SetJustifyH("LEFT")
    bundleHint:SetText("Collects your utility vanity items (anvils, call boards, altars, retreat scrolls, and more).")

    local delBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delBtn:SetSize(210, 24)
    delBtn:SetText("Delete Fel Warchest items")
    delBtn:SetPoint("TOPLEFT", bundleHint, "BOTTOMLEFT", -2, -18)
    delBtn:SetScript("OnClick", ns.DeleteFelItems)

    local delHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    delHint:SetPoint("TOPLEFT", delBtn, "BOTTOMLEFT", 2, -6)
    delHint:SetWidth(360); delHint:SetJustifyH("LEFT")
    delHint:SetText("Removes the Fel Enchanted Warchest's leftover items from your bags.")

    local dupBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    dupBtn:SetSize(210, 24)
    dupBtn:SetText("Delete duplicate vanity items")
    dupBtn:SetPoint("TOPLEFT", delHint, "BOTTOMLEFT", -2, -14)
    dupBtn:SetScript("OnClick", ns.DeleteDuplicateVanity)

    local dupHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dupHint:SetPoint("TOPLEFT", dupBtn, "BOTTOMLEFT", 2, -6)
    dupHint:SetWidth(360); dupHint:SetJustifyH("LEFT")
    dupHint:SetText("Removes vanity items from your bags that you already own in your collection.")

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
