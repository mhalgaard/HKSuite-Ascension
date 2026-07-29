local ADDON, ns = ...

-- =============================================================================
-- Auto Summon Premium Pets module.
-- Faithful port of the Ascension WeakAura (rev 17). Exception requested by user:
-- Wondrous Wisdomball is only summoned in NORMAL-difficulty dungeons.
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

local function summonPet(idx)
    lastSummonTime = GetTime()
    lastSummonedZone = currentZoneToken()
    afterDelay(0.2, function() CallCompanion("CRITTER", idx) end)
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

local LOOTBOT = "Lootbot 3000"

-- With the Loot-Transfigurator owned the Lootbot adds nothing, so it is replaced
-- wherever a context asks for it -- the surrounding priority is untouched, the
-- Lootbot's slot in it just goes to something else. Your safe-zone pet takes that
-- slot if you have named one, otherwise Fix-o-Tron does.
--
-- This used to be `table.remove(list, 1)` on the open-world list, which was wrong
-- twice over: it never applied in Manastorm, dungeons or raids, and while
-- levelling position 1 is the Book of Ascension, so it dropped the Book and left
-- the Lootbot in place.
local function substituteLootbot(list)
    if not (cfg.lootTrans and findPetIndex("Loot-Transfigurator")) then return list end

    local replacement = cfg.safeZonePet
    if not replacement or replacement == "" then replacement = "Fix-o-Tron" end

    -- The replacement is often already further down the list, so de-duplicate as
    -- we go and let it keep the earlier (Lootbot's) position.
    local out, seen = {}, {}
    for _, name in ipairs(list) do
        local pick = (name == LOOTBOT) and replacement or name
        if not seen[pick] then
            seen[pick] = true
            out[#out + 1] = pick
        end
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

    -- Safe zone (resting / AFK): custom pet then Book.
    if IsResting() or UnitIsAFK("player") then
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
    return substituteLootbot(contextPriorityList())
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
        label = "Only summon after a zone change",
        tooltip = "Avoids re-summoning until you move to a different zone.",
        get = function() return cfg.noResummon end,
        set = function(v) cfg.noResummon = v end,
    })
    page:Check({
        label = "Skip Lootbot if Loot-Transfigurator is owned",
        tooltip = "The Lootbot adds nothing once you own the Loot-Transfigurator, so its slot in "
            .. "the priority goes to something else instead.\n\nEvery situation keeps its normal "
            .. "priority; only the Lootbot is swapped out, for your safe-zone pet if you have "
            .. "named one, otherwise Fix-o-Tron.",
        get = function() return cfg.lootTrans end,
        set = function(v) cfg.lootTrans = v end,
    })
    page:Hint("Only takes effect while you actually own the Loot-Transfigurator.")

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
            .. "Also stands in for the Lootbot everywhere, if the option above is on.\n\n"
            .. "Matched as a substring, so part of the name is enough.",
        get = function() return cfg.safeZonePet or "" end,
        set = function(v) cfg.safeZonePet = v end,
    })

    -- Spell out the priority: which pet you get is otherwise hard to predict.
    page:Header("Summon priority by situation")
    page:Text("Highest available pet you own wins; PvP/arena summons nothing.")
    page:Text(
        "• Manastorm:  Cogsley (Eye of the Manastorm)  >  Lootbot 3000\n" ..
        "• Dungeon (Normal):  Wisdomball (first 15s of the run or right after an LFG completion)  >  Lootbot 3000\n" ..
        "• Raid:  Lootbot 3000\n" ..
        "• Open world:  Lootbot 3000  >  Book of Ascension  >  Treasure Keeper  >  Fix-o-Tron\n" ..
        "• While leveling (before your first LFG completion):  Book of Ascension leads\n" ..
        "• Resting / AFK in a safe zone:  your safe-zone pet (above)  >  Book of Ascension"
    )
    page:Text("With \"Skip Lootbot\" on and the Loot-Transfigurator owned, every Lootbot 3000 above "
        .. "becomes your safe-zone pet (or Fix-o-Tron if you haven't named one). Nothing else about "
        .. "the order changes.")
    page:Hint("Wisdomball is only used in Normal dungeons, never Heroic/Mythic.")
end

function M:OnInit()
    cfg = ns.GetConfig("pets")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("LFG_COMPLETION_REWARD")
    ev:RegisterEvent("COMPANION_LEARNED")
    ev:RegisterEvent("COMPANION_UNLEARNED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            invalidateCompanions()   -- indices are not stable across a reload
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
        end
    end)

    startTicker(2, choosePet)   -- matches the WeakAura's 2-second cadence
end
