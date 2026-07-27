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
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Rolling"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Rolling")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(520)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Shortens the roll animation when rolling abilities and talents, by setting the client's "
        .. GLOBAL .. " global. Turning it off restores the value the client had before HKSuite touched it.")

    local quick = ns.CreateCheck(panel, "Enable quick rolling",
        "Sets " .. GLOBAL .. " to the duration below, the same as running\n"
        .. "|cffffd100/run setglobal(\"" .. GLOBAL .. "\", 0)|r\nafter every reload.",
        cfg.quickRoll)
    quick:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)

    local durLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    durLabel:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", 24, -8)
    durLabel:SetText("Roll duration while quick rolling (seconds, 0 = instant):")

    local durBox = CreateFrame("EditBox", "HKSuiteRollDurationBox", panel, "InputBoxTemplate")
    durBox:SetSize(76, 20)   -- room for the digits plus the inline check
    durBox:SetAutoFocus(false)
    durBox:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 4, -8)
    durBox:SetText(tostring(cfg.duration or 0))

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", durBox, "BOTTOMLEFT", 0, -12)

    local function RefreshStatus()
        status:SetText("Value at load: " .. FormatValue(original)
            .. "   |cff808080|||r   now: " .. FormatValue(_G[GLOBAL]))
    end

    local function SaveDuration()
        local v = tonumber((durBox:GetText() or ""):match("[%d%.]+") or "") or 0
        if v < 0 then v = 0 elseif v > 60 then v = 60 end
        cfg.duration = v
        durBox:SetText(tostring(v))
        Apply()
        RefreshStatus()
    end

    durBox:SetScript("OnEnterPressed", function(self) SaveDuration(); self:ClearFocus() end)
    durBox:SetScript("OnEditFocusLost", SaveDuration)
    durBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(cfg.duration or 0)); self:ClearFocus()
    end)

    ns.CreateInlineAccept(durBox, SaveDuration)

    quick:SetScript("OnClick", function(self)
        cfg.quickRoll = self:GetChecked() and true or false
        Apply()
        RefreshStatus()
    end)

    panel:SetScript("OnShow", function()
        quick:SetChecked(cfg.quickRoll)
        durBox:SetText(tostring(cfg.duration or 0))
        RefreshStatus()
    end)

    RefreshStatus()
    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("rolling")

    Snapshot()          -- before anything writes to the global
    BuildOptionsPanel()
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
