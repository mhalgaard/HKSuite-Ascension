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
local function findPetIndex(name)
    for i = 1, GetNumCompanions("CRITTER") do
        local _, cname = GetCompanionInfo("CRITTER", i)
        if cname and cname:find(name, 1, true) then
            return i, cname
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

local function buildPriorityList()
    -- Manastorm: Cogsley (ideally with the Eye buff) then Lootbot.
    if inManastorm() then
        return { "Cogsley", "Lootbot 3000" }
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
            table.insert(list, "Lootbot 3000")
            return list
        elseif instanceType == "raid" then
            return { "Lootbot 3000" }
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
    local list
    if leveling then
        list = { "Book of Ascension", "Lootbot 3000", "Treasure Keeper", "Fix-o-Tron" }
    else
        list = { "Lootbot 3000", "Book of Ascension", "Treasure Keeper", "Fix-o-Tron" }
    end
    if cfg.lootTrans and findPetIndex("Loot-Transfigurator") then
        table.remove(list, 1)   -- drop Lootbot if the Transfigurator is owned
    end
    return list
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
        tooltip = "Removes Lootbot 3000 from the priority when you own the Loot-Transfigurator.",
        get = function() return cfg.lootTrans end,
        set = function(v) cfg.lootTrans = v end,
    })

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
        tooltip = "Summoned instead of the usual priority while resting or AFK in a safe zone.",
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
    page:Hint("Wisdomball is only used in Normal dungeons, never Heroic/Mythic.")
end

function M:OnInit()
    cfg = ns.GetConfig("pets")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("LFG_COMPLETION_REWARD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            local _, itype = GetInstanceInfo()
            if IsInInstance() and itype == "party" then
                dungeonEnterTime = GetTime()
            end
            -- Delay so companion data is loaded, then summon if nothing is out.
            afterDelay(3, summonOnLogin)
        elseif event == "LFG_COMPLETION_REWARD" then
            lfgCompleteTime = GetTime()
            lfgEverCompleted = true
        end
    end)

    startTicker(2, choosePet)   -- matches the WeakAura's 2-second cadence
end
