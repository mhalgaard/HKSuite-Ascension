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

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Auto-Grab Vanity"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auto-Grab Vanity")

    local gl = ns.CreateCheck(panel, "Grab unlearned vanity on login",
        "Automatically deliver any unlearned vanity spells you own shortly after logging in.", cfg.grabOnLogin)
    gl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    gl:SetScript("OnClick", function(self) cfg.grabOnLogin = self:GetChecked() and true or false end)

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(140, 24)
    btn:SetText("Grab now")
    btn:SetPoint("TOPLEFT", gl, "BOTTOMLEFT", 0, -14)
    btn:SetScript("OnClick", ns.GrabVanity)

    local felBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    felBtn:SetSize(220, 24)
    felBtn:SetText("Grab Fel Enchanted Warchest")
    felBtn:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
    felBtn:SetScript("OnClick", function() ns.GrabVanityByName("Fel Enchanted Warchest") end)

    InterfaceOptions_AddCategory(panel)
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
