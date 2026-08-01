local ADDON, ns = ...

-- =============================================================================
-- Auto Summon Premium Pets module.
-- Faithful port of the Ascension WeakAura (rev 17). Exceptions requested by user:
--   * Wondrous Wisdomball is only summoned in NORMAL-difficulty dungeons.
--   * With the Loot-Transfigurator owned, a raid summons Fix-o-Tron (repairs)
--     rather than the Lootbot the WeakAura asked for.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "pets",
    title = "Auto Summon Pets",
    desc  = "Summons the right premium pet for your current context.",
    defaultEnabled = false,
})

ns.defaults.pets = {
    recastDelay    = 8,       -- seconds between summon attempts (0-600)
    summonInCombat = false,   -- allow summoning while in combat
    noResummon     = false,   -- only summon after a zone change
    lootTrans      = false,   -- skip Lootbot if Loot-Transfigurator is owned
    safeZonePet    = "",      -- preferred pet name in rest/AFK zones
    keepWhileResting = true,  -- never swap out a pet that is already out while resting
    restZones      = "",      -- extra zones to treat as resting (comma separated)
}

local cfg

-- State
local lastSummonTime   = 0
local lastSummonedZone = nil
local dungeonEnterTime = nil
local lfgCompleteTime  = nil
local lfgEverCompleted = false

-- Scheduling helpers (Ascension provides C_Timer; fall back just in case).
local function afterDelay(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end
local function startTicker(interval, fn)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(interval, fn)
    else
        local acc, t = 0, CreateFrame("Frame")
        t:SetScript("OnUpdate", function(_, e)
            acc = acc + e
            if acc >= interval then acc = 0 fn() end
        end)
    end
end

-- State helpers
local function hasAura(fn, name)
    for i = 1, 40 do
        local n = fn("player", i)
        if not n then break end
        if n == name then return true end
    end
    return false
end
local function hasBuff(name)   return hasAura(UnitBuff, name) end
local function hasDebuff(name) return hasAura(UnitDebuff, name) end

local function isCasting()
    return UnitCastingInfo("player") or UnitChannelInfo("player")
end

local function inManastorm()
    if C_Manastorm and C_Manastorm.IsInManastorm then
        local ok, res = pcall(C_Manastorm.IsInManastorm)
        return ok and res
    end
    return false
end

local function currentZoneToken()
    return (GetZoneText() or "") .. "|" .. (GetSubZoneText() or "")
end

-- ------------------------------------------------------------- "am I safe here"
-- Ascension does not flag its capitals as resting -- standing in Orgrimmar,
-- IsResting() is false -- so the inn/city test can't be IsResting() alone. The
-- capital names are matched directly, plus anything the realm marks as a sanctuary
-- (Dalaran and Shattrath in stock WotLK), plus whatever you list yourself for the
-- custom hubs a private server invents.
local CITY_ZONES = {
    ["orgrimmar"] = true, ["thunder bluff"] = true, ["undercity"] = true,
    ["silvermoon city"] = true,
    ["stormwind city"] = true, ["ironforge"] = true, ["darnassus"] = true,
    ["the exodar"] = true,
    ["shattrath city"] = true, ["dalaran"] = true,
}

-- Parsed form of cfg.restZones, rebuilt only when the setting's text changes.
local restZonesRaw, restZonesList

local function extraRestZones()
    local raw = cfg.restZones or ""
    if raw ~= restZonesRaw then
        restZonesRaw, restZonesList = raw, {}
        for piece in raw:gmatch("[^,]+") do
            local name = piece:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then restZonesList[#restZonesList + 1] = name end
        end
    end
    return restZonesList
end

local function inSafeCity()
    local zone = (GetZoneText() or ""):lower()
    if CITY_ZONES[zone] then return true end

    if GetZonePVPInfo and GetZonePVPInfo() == "sanctuary" then return true end

    local extras = extraRestZones()
    if #extras > 0 then
        local sub = (GetSubZoneText() or ""):lower()
        for _, name in ipairs(extras) do
            if zone:find(name, 1, true) or sub:find(name, 1, true) then return true end
        end
    end
    return false
end

-- Resting proper, or somewhere that ought to count as resting.
local function inRestArea()
    return IsResting() or inSafeCity()
end

-- Companion lookup (name substring match, like the WeakAura).
--
-- The names and their indices only move when the collection itself changes, but
-- a priority pass asks about several pets and the ticker runs every 2 seconds --
-- so looking each one up live meant walking the entire companion list once per
-- candidate, forever. On a big vanity collection that is thousands of
-- GetCompanionInfo calls a second. Walk it once and reuse the result.
local companionCache, companionCacheAt
local COMPANION_TTL = 10

local function invalidateCompanions()
    companionCache = nil
end

local function companionList()
    if companionCache and (GetTime() - companionCacheAt) < COMPANION_TTL then
        return companionCache
    end
    local list = {}
    for i = 1, GetNumCompanions("CRITTER") do
        local _, cname = GetCompanionInfo("CRITTER", i)
        if cname then list[#list + 1] = { idx = i, name = cname } end
    end
    companionCache, companionCacheAt = list, GetTime()
    return list
end

local function findPetIndex(name)
    for _, entry in ipairs(companionList()) do
        if entry.name:find(name, 1, true) then
            return entry.idx, entry.name
        end
    end
end

-- Is any companion currently summoned?
local function anyPetActive()
    for i = 1, GetNumCompanions("CRITTER") do
        local _, _, _, _, active = GetCompanionInfo("CRITTER", i)
        if active then return true end
    end
    return false
end

-- Same answer, memoised. The ticker asks every two seconds and the scan walks the
-- whole collection, which is the cost the companion cache above exists to avoid --
-- so hold the answer until something actually changes a companion's state.
-- COMPANION_UPDATE covers summoning, dismissing and anything done by hand.
local petOutKnown, petOutValue = false, false

local function invalidatePetOut() petOutKnown = false end

local function isPetOut()
    if not petOutKnown then
        petOutValue = anyPetActive()
        petOutKnown = true
    end
    return petOutValue
end

local function summonPet(idx)
    lastSummonTime = GetTime()
    lastSummonedZone = currentZoneToken()
    afterDelay(0.2, function()
        CallCompanion("CRITTER", idx)
        invalidatePetOut()
    end)
end

local function canAttemptSummon()
    if UnitIsDeadOrGhost("player") then return false end
    if IsMounted() then return false end
    if isCasting() then return false end
    if IsStealthed() or hasBuff("Invisibility") or hasBuff("Mass Invisibility") then return false end
    if hasDebuff("Smite Stomp") then return false end
    if UnitAffectingCombat("player") and not cfg.summonInCombat then return false end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "arena" or instanceType == "pvp" then return false end   -- no pet in PvP

    if (GetTime() - lastSummonTime) < (cfg.recastDelay or 8) then return false end

    if cfg.noResummon and lastSummonedZone == currentZoneToken() then return false end

    return true
end

local LOOTBOT   = "Lootbot 3000"
local REPAIRBOT = "Fix-o-Tron"      -- "Fix-o-Tron 5000" in game; matched as a substring

-- The Loot-Transfigurator is an ITEM (item:190190, "Loot-Transfigurator 5000"),
-- not a companion. The ownership gate here used to be findPetIndex(), which walks
-- the CRITTER companion list -- so it could never match, the substitution never
-- ran, and every context kept summoning the Lootbot. The setting itself is now
-- what decides; the item id is only used to report what we can see in the
-- settings page, since an unlock consumed on use would leave nothing to find.
local LOOT_TRANSFIGURATOR_ITEM = 190190

local function transfiguratorInBags()
    if type(GetItemCount) ~= "function" then return false end
    local ok, n = pcall(GetItemCount, LOOT_TRANSFIGURATOR_ITEM, true)   -- include bank
    return ok and (n or 0) > 0
end

-- Which pet takes the Lootbot's place. In a raid it is always the repair bot --
-- repairing mid-raid is the whole point of having it out, whatever pet you prefer
-- while resting. Everywhere else your safe-zone pet wins if you named one.
local function lootbotStandIn()
    if IsInInstance() then
        local _, instanceType = GetInstanceInfo()
        if instanceType == "raid" then return REPAIRBOT end
    end
    if cfg.safeZonePet and cfg.safeZonePet ~= "" then return cfg.safeZonePet end
    return REPAIRBOT
end

-- With the Loot-Transfigurator owned the Lootbot adds nothing, so the pet you'd
-- rather have goes in ahead of it wherever a context asks for the Lootbot. The
-- Lootbot stays on at the back as a fallback, so a character that doesn't own the
-- stand-in still gets a pet instead of none.
--
-- This used to be `table.remove(list, 1)` on the open-world list, which was wrong
-- twice over: it never applied in Manastorm, dungeons or raids, and while
-- levelling position 1 is the Book of Ascension, so it dropped the Book and left
-- the Lootbot in place.
local function preferOverLootbot(list)
    if not cfg.lootTrans then return list end

    local standIn = lootbotStandIn()
    -- The stand-in is often already further down the list, so de-duplicate as we
    -- go and let it keep the earlier (Lootbot's) position.
    local out, seen = {}, {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    for _, name in ipairs(list) do
        if name == LOOTBOT then add(standIn) end
        add(name)
    end
    return out
end

local function contextPriorityList()
    -- Manastorm: Cogsley (ideally with the Eye buff) then Lootbot.
    if inManastorm() then
        return { "Cogsley", LOOTBOT }
    end

    local _, instanceType, difficultyIndex = GetInstanceInfo()
    if IsInInstance() then
        if instanceType == "party" then
            local list = {}
            -- Wisdomball ONLY in Normal dungeons (difficultyIndex 1), and only
            -- in the first 15s of the run or just after an LFG completion.
            if difficultyIndex == 1 then
                local recent = dungeonEnterTime and (GetTime() - dungeonEnterTime) <= 15
                local postLFG = lfgCompleteTime and (GetTime() - lfgCompleteTime) <= 60
                if recent or postLFG then
                    table.insert(list, "Wondrous Wisdomball")
                end
            end
            table.insert(list, LOOTBOT)
            return list
        elseif instanceType == "raid" then
            return { LOOTBOT }
        end
    end

    -- Safe zone (resting / city / AFK): custom pet then Book.
    if inRestArea() or UnitIsAFK("player") then
        local list = {}
        if cfg.safeZonePet and cfg.safeZonePet ~= "" then table.insert(list, cfg.safeZonePet) end
        table.insert(list, "Book of Ascension")
        return list
    end

    -- Open world. While still leveling (before first LFG completion), the WA
    -- prefers the Book; otherwise Lootbot leads.
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 80
    local leveling = UnitLevel("player") < maxLevel and not lfgEverCompleted
    if leveling then
        return { "Book of Ascension", LOOTBOT, "Treasure Keeper", "Fix-o-Tron" }
    end
    return { LOOTBOT, "Book of Ascension", "Treasure Keeper", "Fix-o-Tron" }
end

local function buildPriorityList()
    return preferOverLootbot(contextPriorityList())
end

-- Summon the highest-priority owned pet for the current context.
local function summonBest()
    for _, petName in ipairs(buildPriorityList()) do
        local idx = findPetIndex(petName)
        if idx then
            summonPet(idx)
            return true
        end
    end
    return false
end

local function choosePet()
    if not ns.IsModuleEnabled("pets") then return end

    -- Resting or in a city: whatever pet you have out is the one you chose to have
    -- out, so the context's preference doesn't get to trade it in. This is
    -- deliberately "don't change", not "don't summon" -- with nothing out there is
    -- no choice to override, and the module would be useless at an inn otherwise.
    if cfg.keepWhileResting and inRestArea() and isPetOut() then return end

    if not canAttemptSummon() then return end

    for _, petName in ipairs(buildPriorityList()) do
        local idx = findPetIndex(petName)
        if idx then
            local _, _, _, _, active = GetCompanionInfo("CRITTER", idx)
            if active then
                return          -- best owned pet already out
            else
                summonPet(idx)  -- summon the highest-priority owned pet
                return
            end
        end
    end
end

-- On login / world entry: if no pet is out at all, summon the best one for the
-- situation. Leaves an already-active pet alone.
local function summonOnLogin()
    if not ns.IsModuleEnabled("pets") then return end
    if anyPetActive() then return end
    if not canAttemptSummon() then return end
    summonBest()
end

-- ---------------------------------------------------------------- Options UI
function M:BuildSettings(page)
    page:Check({
        label = "Summon while in combat",
        tooltip = "Allow summoning premium pets during combat.",
        get = function() return cfg.summonInCombat end,
        set = function(v) cfg.summonInCombat = v end,
    })
    page:Check({
        label = "Never change my pet while resting or in a city",
        tooltip = "In a rest area, a pet you already have out is left alone -- the module won't "
            .. "swap it for the one it would normally pick.\n\nWith nothing out it still summons, "
            .. "so you get a pet at an inn; it just never overrides a choice you made yourself."
            .. "\n\nAscension doesn't flag its capitals as resting, so the capital city names count "
            .. "as a rest area too, along with any sanctuary and anything you list below.",
        get = function() return cfg.keepWhileResting end,
        set = function(v) cfg.keepWhileResting = v end,
    })
    page:Check({
        label = "Only summon after a zone change",
        tooltip = "Avoids re-summoning until you move to a different zone.",
        get = function() return cfg.noResummon end,
        set = function(v) cfg.noResummon = v end,
    })
    page:Check({
        label = "I own the Loot-Transfigurator 5000 (skip the Lootbot)",
        tooltip = "The Lootbot adds nothing once you own the Loot-Transfigurator, so the pet you'd "
            .. "rather have goes ahead of it in every situation.\n\nIn a raid that is always "
            .. "Fix-o-Tron, so you have repairs with you. Elsewhere it is your safe-zone pet if you "
            .. "named one, otherwise Fix-o-Tron.\n\nThe Lootbot stays on as a fallback, so you still "
            .. "get a pet if you don't own the stand-in.",
        get = function() return cfg.lootTrans end,
        set = function(v) cfg.lootTrans = v end,
    })

    -- The Transfigurator is an item, and an unlock consumed on use would leave
    -- nothing to look for -- so this setting is a declaration, not a detection.
    -- Report what we can actually see, and leave the choice to you.
    local function OwnStatus()
        if transfiguratorInBags() then
            return "|cff1eff00Loot-Transfigurator 5000 found on this character.|r"
        end
        return "|cffaaaaaaNot in your bags or bank on this character -- the tick above is what "
            .. "counts, so leave it on if you own it anyway.|r"
    end
    local status = page:Hint(OwnStatus())
    page:OnRefresh(function() status:SetText(OwnStatus()) end)

    page:Spacer(6)
    page:Slider({
        name = "HKSuitePetDelaySlider",
        label = "Recast delay", min = 0, max = 600, step = 1, width = 240,
        tooltip = "How long to wait before summoning again.",
        format = function(v) return v .. "s" end,
        get = function() return cfg.recastDelay or 8 end,
        set = function(v) cfg.recastDelay = v end,
    })

    page:Input({
        label = "Safe-zone pet (name)",
        name = "HKSuitePetSafeZone", width = 200,
        tooltip = "Summoned instead of the usual priority while resting or AFK in a safe zone.\n\n"
            .. "Also stands in for the Lootbot outside raids, if the option above is on. In a raid "
            .. "the stand-in is always Fix-o-Tron.\n\n"
            .. "Matched as a substring, so part of the name is enough.",
        get = function() return cfg.safeZonePet or "" end,
        set = function(v) cfg.safeZonePet = v end,
    })

    page:Input({
        label = "Extra rest zones",
        name = "HKSuitePetRestZones", width = 300,
        tooltip = "Comma-separated zone or sub-zone names to treat as a rest area, on top of "
            .. "actual resting, the capital cities and any sanctuary.\n\n"
            .. "For a custom hub this realm invents that none of those cover.\n\n"
            .. "Matched as a substring, so part of the name is enough.",
        get = function() return cfg.restZones or "" end,
        set = function(v) cfg.restZones = v end,
    })
    page:Hint("Rest areas already cover: resting, the ten capital cities, and sanctuary zones.")

    -- Spell out the priority: which pet you get is otherwise hard to predict.
    page:Header("Summon priority by situation")
    page:Text("Highest available pet you own wins; PvP/arena summons nothing.")
    page:Text(
        "• Manastorm:  Cogsley (Eye of the Manastorm)  >  Lootbot 3000\n" ..
        "• Dungeon (Normal):  Wisdomball (first 15s of the run or right after an LFG completion)  >  Lootbot 3000\n" ..
        "• Raid:  Fix-o-Tron (with the Loot-Transfigurator ticked)  >  Lootbot 3000\n" ..
        "• Open world:  Lootbot 3000  >  Book of Ascension  >  Treasure Keeper  >  Fix-o-Tron\n" ..
        "• While leveling (before your first LFG completion):  Book of Ascension leads\n" ..
        "• Resting / in a city / AFK:  your safe-zone pet (above)  >  Book of Ascension"
    )
    page:Text("With the Loot-Transfigurator ticked above, a stand-in goes in ahead of every "
        .. "Lootbot 3000 in that list -- Fix-o-Tron in a raid, your safe-zone pet (or Fix-o-Tron) "
        .. "anywhere else. The Lootbot keeps its place behind the stand-in as a fallback, and "
        .. "nothing else about the order changes.")
    page:Hint("Wisdomball is only used in Normal dungeons, never Heroic/Mythic.")
    page:Hint("In a rest area, none of this replaces a pet you already have out unless you untick "
        .. "\"Never change my pet while resting or in a city\" above.")
end

function M:OnInit()
    cfg = ns.GetConfig("pets")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("LFG_COMPLETION_REWARD")
    ev:RegisterEvent("COMPANION_LEARNED")
    ev:RegisterEvent("COMPANION_UNLEARNED")
    ev:RegisterEvent("COMPANION_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "COMPANION_UPDATE" then
            invalidatePetOut()       -- something was summoned or dismissed
        elseif event == "PLAYER_ENTERING_WORLD" then
            invalidateCompanions()   -- indices are not stable across a reload
            invalidatePetOut()
            local _, itype = GetInstanceInfo()
            if IsInInstance() and itype == "party" then
                dungeonEnterTime = GetTime()
            end
            -- Delay so companion data is loaded, then summon if nothing is out.
            afterDelay(3, summonOnLogin)
        elseif event == "LFG_COMPLETION_REWARD" then
            lfgCompleteTime = GetTime()
            lfgEverCompleted = true
        else
            invalidateCompanions()   -- collection changed, so the cache is stale
            invalidatePetOut()
        end
    end)

    startTicker(2, choosePet)   -- matches the WeakAura's 2-second cadence
end
