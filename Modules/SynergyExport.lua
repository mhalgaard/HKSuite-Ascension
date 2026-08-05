local ADDON, ns = ...

-- =============================================================================
-- Synergy Export: copy this character to the Ascension Synergy website.
--
-- Produces a plain key=value block rather than a binary blob so a human can see
-- exactly what is being shared, and so the site can parse it without a decoder.
-- The game's own C_CharacterAdvancement.ExportBuild string is included too, which
-- is what lets the build be re-imported in game.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "synergyexport",
    title = "Synergy Export",
    desc  = "Export this character's stats, abilities and talents for the Ascension Synergy site.",
})

ns.defaults.synergyexport = {
    includeStats = true,
    includeBuild = true,
}

local cfg
local FORMAT_VERSION = "ASYN1"

-- ------------------------------------------------------------------ helpers

--- pcall wrapper that returns nil instead of propagating, so one missing API
--- cannot break the whole export.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

local function round(v, places)
    if type(v) ~= "number" then return nil end
    local mult = 10 ^ (places or 0)
    return math.floor(v * mult + 0.5) / mult
end

-- ------------------------------------------------------------------ stats

local function collectStats()
    local out = {}
    local CA = C_CharacterAdvancement

    out.name = UnitName("player")
    out.realm = GetRealmName and GetRealmName() or nil
    out.level = UnitLevel("player")

    -- The applied Path, not the selected one: they desync, and only the applied
    -- one is actually granting stat scaling.
    out.path = safe(GetUnitPrimaryStat, "player")

    -- UnitStat returns base, current, posBuff, negBuff. Exporting BOTH matters: the
    -- site re-applies buffs you toggle on, so feeding it already-buffed numbers would
    -- double-count them. Base is the calculation input; current is for cross-checking.
    local buffed = false
    local function stat(index)
        local ok, base, current, pos, neg = pcall(UnitStat, "player", index)
        if not ok then return nil, nil end
        if (pos or 0) ~= 0 or (neg or 0) ~= 0 then buffed = true end
        return base, current
    end

    out.str, out.strNow = stat(1)
    out.agi, out.agiNow = stat(2)
    out.sta, out.staNow = stat(3)
    out.int, out.intNow = stat(4)
    out.spi, out.spiNow = stat(5)

    -- UnitAttackPower returns base, posBuff, negBuff -- no "current", so total is summed.
    local function power(fn)
        local ok, base, pos, neg = pcall(fn, "player")
        if not ok then return nil, nil end
        if (pos or 0) ~= 0 or (neg or 0) ~= 0 then buffed = true end
        return base, (base or 0) + (pos or 0) + (neg or 0)
    end

    out.ap, out.apNow = power(UnitAttackPower)
    out.rap, out.rapNow = power(UnitRangedAttackPower)

    -- Flags that buffs were up at export time, so the site can warn instead of
    -- silently mixing a buffed baseline with buffs you toggle on.
    out.buffed = buffed and 1 or 0

    -- Highest school bonus; index 1 is physical.
    local sp = 0
    for school = 2, 7 do
        local v = safe(GetSpellBonusDamage, school)
        if type(v) == "number" and v > sp then sp = v end
    end
    out.sp = sp

    -- Weapon damage, for abilities that deal a percentage of it (Sinister Strike and
    -- friends). UnitDamage returns low, high, offLow, offHigh, posBuff, negBuff, percent.
    local okDmg, low, high, offLow, offHigh, dmgPos, dmgNeg, dmgPct = pcall(UnitDamage, "player")
    if okDmg then
        out.wpnLow = round(low, 1)
        out.wpnHigh = round(high, 1)
        out.wpnOffLow = round(offLow, 1)
        out.wpnOffHigh = round(offHigh, 1)
        -- Included so the site can back out temporary weapon buffs if it needs to.
        out.wpnPos = round(dmgPos, 1)
        out.wpnNeg = round(dmgNeg, 1)
        out.wpnPct = round(dmgPct, 3)
        if (dmgPos or 0) ~= 0 or (dmgNeg or 0) ~= 0 then buffed = true end
    end

    -- Speeds matter for normalized-weapon abilities and for DPS comparisons.
    local okSpeed, mainSpeed, offSpeed = pcall(UnitAttackSpeed, "player")
    if okSpeed then
        out.wpnSpeed = round(mainSpeed, 2)
        out.wpnOffSpeed = round(offSpeed, 2)
    end

    out.crit = round(safe(GetSpellCritChance, 2), 2)
    out.mcrit = round(safe(GetCritChance), 2)
    out.rcrit = round(safe(GetRangedCritChance), 2)

    -- Budgets straight from the game beats hardcoding them on the website.
    if CA then
        out.aeMax = safe(CA.GetExpectedAE, out.level)
        out.teMax = safe(CA.GetExpectedTE, out.level)
    end

    return out
end

-- ------------------------------------------------------- abilities/talents

--- Walks the full catalog and keeps what this character actually knows.
--- Uses the same filter walk as the catalog export, then IsKnownID per entry --
--- there is no "list my picks" API, and this needs no class/tab enum knowledge.
local function collectPicks()
    local CA = C_CharacterAdvancement
    local abilities, talents = {}, {}
    if not CA then return abilities, talents end

    if not pcall(CA.SetFilteredEntries, "", {}) then
        return abilities, talents
    end

    local index, misses = 1, 0
    while misses < 50 and index <= 500000 do
        local ok, entry = pcall(CA.GetFilteredEntryAtIndex, index)
        if ok and type(entry) == "table" and entry.ID then
            misses = 0
            if safe(CA.IsKnownID, entry.ID) then
                -- GetTalentRankByID only answers for talents, so abilities exported
                -- without a rank and the website had to guess theirs. Fall back through
                -- the spell-keyed lookup and the entry's own Points before giving up.
                local rank = safe(CA.GetTalentRankByID, entry.ID)
                if not rank or rank < 1 then
                    local firstSpell = type(entry.Spells) == "table" and entry.Spells[1] or entry.Spells
                    if firstSpell then rank = safe(CA.GetTalentRankBySpellID, firstSpell) end
                end
                if (not rank or rank < 1) and type(entry.Points) == "number" and entry.Points > 0 then
                    rank = entry.Points
                end

                local record = { id = entry.ID, rank = rank, name = entry.Name }
                if safe(CA.IsTalentID, entry.ID) then
                    talents[#talents + 1] = record
                else
                    abilities[#abilities + 1] = record
                end
            end
        else
            misses = misses + 1
        end
        index = index + 1
    end

    return abilities, talents
end

local function joinPicks(list)
    local parts = {}
    for i = 1, #list do
        local p = list[i]
        -- Always emit the rank when known. Omitting rank 1 saved a few characters but
        -- left the website unable to tell "rank 1" from "rank unknown", which is exactly
        -- the distinction it needs to preselect the right rank.
        parts[i] = p.rank and p.rank >= 1 and (p.id .. ":" .. p.rank) or tostring(p.id)
    end
    return table.concat(parts, ",")
end

-- ------------------------------------------------------------------ export

local function BuildExportString()
    local lines = { FORMAT_VERSION }
    local function put(key, value)
        if value ~= nil and value ~= "" then lines[#lines + 1] = key .. "=" .. tostring(value) end
    end

    if cfg.includeStats then
        local s = collectStats()
        put("name", s.name)
        put("realm", s.realm)
        put("level", s.level)
        put("path", s.path)
        -- Unsuffixed keys are BASE (unbuffed); *Now keys are the current buffed values.
        put("str", s.str);  put("agi", s.agi);  put("int", s.int)
        put("spi", s.spi);  put("sta", s.sta)
        put("strNow", s.strNow); put("agiNow", s.agiNow); put("intNow", s.intNow)
        put("spiNow", s.spiNow); put("staNow", s.staNow)
        put("ap", s.ap);    put("rap", s.rap);  put("sp", s.sp)
        put("apNow", s.apNow); put("rapNow", s.rapNow)
        put("buffed", s.buffed)
        put("crit", s.crit); put("mcrit", s.mcrit); put("rcrit", s.rcrit)
        put("wpnLow", s.wpnLow); put("wpnHigh", s.wpnHigh); put("wpnSpeed", s.wpnSpeed)
        put("wpnOffLow", s.wpnOffLow); put("wpnOffHigh", s.wpnOffHigh); put("wpnOffSpeed", s.wpnOffSpeed)
        put("aeMax", s.aeMax); put("teMax", s.teMax)
    end

    local abilities, talents = collectPicks()
    put("abilities", joinPicks(abilities))
    put("talents", joinPicks(talents))

    if cfg.includeBuild then
        -- The game's own export code, so the build can be re-imported in game.
        put("build", safe(C_CharacterAdvancement and C_CharacterAdvancement.ExportBuild, false))
    end

    return table.concat(lines, "\n"), #abilities, #talents
end

-- Cached so the TextArea's get() doesn't rebuild (and rescan the catalog) on
-- every UI refresh.
local cached, cachedCounts = nil, nil

local function Regenerate()
    local text, nAbilities, nTalents = BuildExportString()
    cached = text
    cachedCounts = { abilities = nAbilities, talents = nTalents }
    return text
end

-- ------------------------------------------------------------------ module

function M:OnInit()
    cfg = ns.GetConfig("synergyexport")
end

function M:BuildSettings(page)
    cfg = cfg or ns.GetConfig("synergyexport")

    page:Hint("Generate, then click in the box, Ctrl+A, Ctrl+C, and paste it into the "
        .. "Import character panel on the Ascension Synergy site.")

    local status
    page:Button({
        text = "Generate export", width = 180,
        tooltip = "Reads your current stats and everything you have learned.",
        onClick = function()
            Regenerate()
            if status then
                status:SetText(("%d abilities, %d talents"):format(
                    cachedCounts.abilities, cachedCounts.talents))
            end
            page:Refresh()
        end,
    })
    status = page:Hint("Not generated yet.")

    page:TextArea({
        label = "Export string",
        name = "HKSuiteSynergyExport", height = 150,
        get = function() return cached or "" end,
        -- Read-only in spirit: edits are discarded so a stray keystroke cannot
        -- corrupt what gets pasted.
        set = function() end,
    })

    page:Header("Include")
    page:Check({
        label = "Character stats",
        tooltip = "Level, Path, primary stats, attack power, spell power and crit.",
        get = function() return cfg.includeStats end,
        set = function(v) cfg.includeStats = v end,
    })
    page:Check({
        label = "In-game build code",
        tooltip = "The game's own ExportBuild string, so the build can be re-imported in game.",
        get = function() return cfg.includeBuild end,
        set = function(v) cfg.includeBuild = v end,
    })
end

-- Exposed so a slash command or another module can reuse it.
ns.BuildSynergyExport = Regenerate
