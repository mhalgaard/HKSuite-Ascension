local ADDON, ns = ...

-- =============================================================================
-- Rolling module -- quick rolling for abilities and talents.
-- -----------------------------------------------------------------------------
-- Runs the community quick-roll script for you:
--     /run setglobal("DEBUG_WC_ROULETTE_DURATION", 0)
-- The client leaves that global undefined, so "off" means putting it back to the
-- value it had at load (normally nil) rather than to some documented default.
-- It is a plain Lua global, so it resets every /reload -- which is why we
-- re-apply on load and on every world change, and why the snapshot is always
-- taken before we write anything.
--
-- Note: setting this to 0 was verified in-game (2026-07-26) to make no visible
-- difference to the roll animation on the current Ascension client. The real
-- quick-rolling implementation is the client's own rapid-roll session on the
-- C_Wildcard API (StartRapidRolling / ContinueRapidRolling / ...), gated by the
-- server config CONFIG_WILDCARD_QUICK_ROLLING_ENABLED. If this module does
-- nothing for you, that is the mechanism to build on instead.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "rolling",
    title = "Rolling",
    desc  = "Quick rolling: shortens the ability/talent roll animation.",
})

ns.defaults.rolling = {
    quickRoll = false,   -- write the global at all
    duration  = 0,       -- seconds the roll spins while quick rolling (0 = instant)
}

local cfg  -- filled in OnInit

local GLOBAL = "DEBUG_WC_ROULETTE_DURATION"

local original, snapshotTaken

local function Snapshot()
    if snapshotTaken then return end
    original = _G[GLOBAL]
    snapshotTaken = true
end

local function FormatValue(v)
    if v == nil then return "|cffaaaaaanil (client default)|r" end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return tostring(v) end
    return "|cffaaaaaa<" .. t .. ">|r"
end

local function Apply()
    Snapshot()
    if ns.IsModuleEnabled("rolling") and cfg.quickRoll then
        _G[GLOBAL] = tonumber(cfg.duration) or 0
    else
        _G[GLOBAL] = original
    end
end

-- -------------------------------------------------------------------- options
function M:BuildSettings(page)
    page:Text("Shortens the roll animation when rolling abilities and talents, by setting the client's "
        .. GLOBAL .. " global. Turning it off restores the value the client had before HKSuite touched it.")

    local status
    local function StatusText()
        return "Value at load: " .. FormatValue(original)
            .. "   |cff808080|||r   now: " .. FormatValue(_G[GLOBAL])
    end
    local function ApplyAndReport()
        Apply()
        if status then status:SetText(StatusText()) end
    end

    page:Check({
        label = "Enable quick rolling",
        tooltip = "Sets " .. GLOBAL .. " to the duration below, the same as running\n"
            .. "|cffffd100/run setglobal(\"" .. GLOBAL .. "\", 0)|r\nafter every reload.",
        get = function() return cfg.quickRoll end,
        set = function(v) cfg.quickRoll = v end,
        onChange = ApplyAndReport,
    })

    page:Input({
        label = "Roll duration while quick rolling (seconds, 0 = instant)",
        name = "HKSuiteRollDurationBox",
        width = 90, numeric = true, min = 0, max = 60,
        get = function() return cfg.duration or 0 end,
        set = function(v) cfg.duration = v end,
        onChange = ApplyAndReport,
    })

    -- The global is a live client value that /hkroll and reloads also move, so
    -- the status line is re-read every time the page comes up.
    status = page:Hint(StatusText())
    page:OnRefresh(function() status:SetText(StatusText()) end)
end

function M:OnInit()
    cfg = ns.GetConfig("rolling")

    Snapshot()          -- before anything writes to the global
    Apply()

    -- The global is per-session, so re-apply whenever the world reloads it away.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", Apply)

    -- The Overview toggles modules without notifying them, so reconcile slowly.
    local poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 1 then return end
        self.elapsed = 0
        Apply()
    end)

    SLASH_HKROLLING1 = "/hkroll"
    SlashCmdList["HKROLLING"] = function(msg)
        local cmd = ((msg or ""):match("^%s*(%S*)") or ""):lower()
        if cmd == "on" or cmd == "off" then
            cfg.quickRoll = (cmd == "on")
            Apply()
        end
        ns.Print("Quick rolling is "
            .. (ns.IsModuleEnabled("rolling") and cfg.quickRoll
                and "|cff1eff00on|r" or "|cffff2020off|r")
            .. ". " .. GLOBAL .. " was " .. FormatValue(original)
            .. ", now " .. FormatValue(_G[GLOBAL])
            .. ". Use /hkroll on|off.")
    end
end
