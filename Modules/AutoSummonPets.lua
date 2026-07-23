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
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Auto Summon Pets"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auto Summon Pets")

    local combat = ns.CreateCheck(panel, "Summon while in combat",
        "Allow summoning premium pets during combat.", cfg.summonInCombat)
    combat:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    combat:SetScript("OnClick", function(self) cfg.summonInCombat = self:GetChecked() and true or false end)

    local noResum = ns.CreateCheck(panel, "Only summon after a zone change",
        "Avoids re-summoning until you move to a different zone.", cfg.noResummon)
    noResum:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -8)
    noResum:SetScript("OnClick", function(self) cfg.noResummon = self:GetChecked() and true or false end)

    local lootT = ns.CreateCheck(panel, "Skip Lootbot if Loot-Transfigurator is owned",
        "Removes Lootbot 3000 from the priority when you own the Loot-Transfigurator.", cfg.lootTrans)
    lootT:SetPoint("TOPLEFT", noResum, "BOTTOMLEFT", 0, -8)
    lootT:SetScript("OnClick", function(self) cfg.lootTrans = self:GetChecked() and true or false end)

    local slider = CreateFrame("Slider", "HKSuitePetDelaySlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", lootT, "BOTTOMLEFT", 4, -28)
    slider:SetMinMaxValues(0, 600)
    slider:SetValueStep(1)
    slider:SetWidth(220)
    _G[slider:GetName() .. "Low"]:SetText("0")
    _G[slider:GetName() .. "High"]:SetText("600")
    _G[slider:GetName() .. "Text"]:SetText("Recast delay: " .. (cfg.recastDelay or 8) .. "s")
    slider:SetValue(cfg.recastDelay or 8)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        cfg.recastDelay = value
        _G[self:GetName() .. "Text"]:SetText("Recast delay: " .. value .. "s")
    end)

    local ebLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ebLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -24)
    ebLabel:SetText("Safe-zone pet (name):")

    local eb = CreateFrame("EditBox", "HKSuitePetSafeZone", panel, "InputBoxTemplate")
    eb:SetSize(180, 20)
    eb:SetPoint("LEFT", ebLabel, "RIGHT", 12, 0)
    eb:SetAutoFocus(false)
    eb:SetText(cfg.safeZonePet or "")
    eb:SetScript("OnEnterPressed", function(self) cfg.safeZonePet = self:GetText() self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(cfg.safeZonePet or "") self:ClearFocus() end)

    -- Explain the summon priority so it's clear what gets summoned when.
    local logicHdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    logicHdr:SetPoint("TOPLEFT", ebLabel, "BOTTOMLEFT", 0, -20)
    logicHdr:SetText("|cffffd100Summon priority by situation|r")

    local logic = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    logic:SetPoint("TOPLEFT", logicHdr, "BOTTOMLEFT", 0, -8)
    logic:SetWidth(520)
    logic:SetJustifyH("LEFT")
    logic:SetSpacing(2)
    logic:SetText(
        "|cffaaaaaaHighest available pet you own wins; PvP/arena summons nothing.|r\n" ..
        "• Manastorm:  Cogsley (Eye of the Manastorm)  >  Lootbot 3000\n" ..
        "• Dungeon (Normal):  Wisdomball (first 15s of the run or right after an LFG completion)  >  Lootbot 3000\n" ..
        "• Raid:  Lootbot 3000\n" ..
        "• Open world:  Lootbot 3000  >  Book of Ascension  >  Treasure Keeper  >  Fix-o-Tron\n" ..
        "• While leveling (before your first LFG completion):  Book of Ascension leads\n" ..
        "• Resting / AFK in a safe zone:  your safe-zone pet (above)  >  Book of Ascension\n" ..
        "|cffaaaaaaWisdomball is only used in Normal dungeons, never Heroic/Mythic.|r"
    )

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("pets")
    BuildOptionsPanel()

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
