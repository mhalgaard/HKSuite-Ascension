local ADDON, ns = ...

-- =============================================================================
-- UI Features module: small on-screen combat helpers.
--   * In-range tracker  â€” a crosshair over the character, white when the target
--     is in melee range, red when it's out of range.
--   * Trinket tracker   â€” a movable box showing your equipped trinkets, greyed
--     out while on cooldown (move with Ctrl + left-drag).
--   * Stat display      â€” your stats as plain text on screen, one toggle per
--     line, laid out as a column or a row.
--   * Loot rolls        â€” a "Loot Rolls" section under the objectives tracker's
--     quests, styled like one of its own blocks, one line per item: the top roll
--     and how much of the group has answered.
--   * Path reminder     â€” a warning over the character while no Path (primary
--     stat) is applied.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "uifeatures",
    title = "UI Features",
    desc  = "In-range crosshair, trinket cooldown tracker, on-screen stat readout, a loot rolls list on the objectives frame, and a missing-Path warning.",
})

ns.defaults.uifeatures = {
    rangeTracker   = false,
    rangeSpell     = "",       -- optional: exact ability name to range-check with
    trinketTracker = false,
    trinketTimerText = true,   -- numeric countdown over the icon (the sweep stays either way)
    trinketPos     = { "CENTER", "CENTER", 0, -160 },  -- point, relPoint, x, y

    -- Stat display: one toggle per line, so a build only lists what it uses.
    statText      = false,
    statPos       = { "CENTER", "CENTER", 220, -160 },
    statLayout    = "vertical",   -- or "horizontal"
    statFontSize  = 12,
    statHideZero  = true,         -- drop lines sitting at zero
    statLocked    = false,        -- locked: no mouse, so clicks pass through it
    statStr = true, statAgi = true, statSta = false, statInt = true, statSpi = true,
    statAP = true, statSP = true,
    statCrit = true, statSpellCrit = false,
    statHit = true, statSpellHit = false,
    statExpertise = true,

    lootRolls           = false,
    lootRollsNeedOnly   = true,  -- only list rolls you answered Need on
    lootRollsMax        = 5,     -- how many recent items the section lists
    lootRollsHideAfter  = 120,   -- hide the section this long after the last roll ended (0 = never)
    lootRollsAttach     = true,  -- sit under the objectives tracker (else a free-floating box)
    lootRollsCollapsed  = false, -- section collapsed to just its header
    lootRollsLimitQuests = true, -- cap the tracker's quest list so the section stays in view
    lootRollsQuestLimit  = 5,
    lootRollsPos        = { "TOPRIGHT", "TOPRIGHT", -220, -260 },

    -- Path reminder: warn while the character has no Path (primary stat) applied.
    pathReminder     = false,
    pathReminderText = "No Path selected!",
    pathReminderY    = 100,      -- pixels above screen centre, i.e. above your character
    pathReminderSize = 18,
}

local cfg  -- filled in OnInit

local function enabled() return ns.IsModuleEnabled("uifeatures") end

-- ------------------------------------------------------------ in-range tracker
-- There's no direct "is target in melee range" API, but IsSpellInRange() is
-- exact for a given ability. Ascension is classless, so instead of assuming a
-- class spell we probe a list of real 5-yard melee abilities and use whichever
-- one the player actually knows (the player can also name their own). We only
-- fall back to the loose CheckInteractDistance (~9.9 yd) if none are found.
local MELEE_SPELLS = {
    -- Rogue
    "Sinister Strike", "Backstab", "Mutilate", "Hemorrhage", "Ghostly Strike", "Gouge", "Eviscerate",
    -- Warrior
    "Rend", "Hamstring", "Mortal Strike", "Bloodthirst", "Overpower", "Revenge",
    "Devastate", "Sunder Armor", "Heroic Strike", "Shield Slam", "Concussion Blow", "Pummel",
    -- Paladin
    "Crusader Strike", "Hammer of the Righteous",
    -- Death Knight
    "Plague Strike", "Blood Strike", "Death Strike", "Obliterate", "Scourge Strike",
    "Frost Strike", "Heart Strike", "Rune Strike",
    -- Hunter (melee)
    "Raptor Strike", "Wing Clip", "Mongoose Bite",
    -- Shaman
    "Stormstrike", "Lava Lash",
    -- Druid
    "Maul", "Mangle (Bear)", "Mangle (Cat)", "Shred", "Claw", "Rake", "Ferocious Bite", "Ravage",
}

local cachedSpell    -- last melee ability that resolved as known
local lastCastSpell  -- most recent spell the player cast (for the "use last" button)

-- IsSpellInRange returns 1 (in range), 0 (out of range), or nil (unknown spell /
-- invalid target). With a valid hostile target, a known melee spell returns 0/1,
-- so a non-nil result reliably means "the player has this ability".
local scanFailedAt          -- when a full probe last came up empty
local RESCAN_AFTER = 5      -- seconds before walking the whole list again

local function InvalidateMeleeSpell()
    cachedSpell, scanFailedAt = nil, nil
end

local function ResolveMeleeSpell()
    local custom = cfg.rangeSpell
    if custom and custom ~= "" and IsSpellInRange(custom, "target") ~= nil then
        return custom
    end
    if cachedSpell and IsSpellInRange(cachedSpell, "target") ~= nil then
        return cachedSpell
    end
    -- A full probe is one IsSpellInRange call per entry in MELEE_SPELLS. Ascension
    -- is classless, so plenty of builds know none of them -- and with no memory of
    -- that we walked the whole list ten times a second for as long as a hostile
    -- target was up. Back off after an empty probe; learning a spell clears it.
    if scanFailedAt and (GetTime() - scanFailedAt) < RESCAN_AFTER then
        return nil
    end
    for _, name in ipairs(MELEE_SPELLS) do
        if IsSpellInRange(name, "target") ~= nil then
            cachedSpell, scanFailedAt = name, nil
            return name
        end
    end
    scanFailedAt = GetTime()
    return nil
end

local function TargetInMeleeRange()
    local spell = ResolveMeleeSpell()
    if spell then
        return IsSpellInRange(spell, "target") == 1
    end
    return CheckInteractDistance("target", 3) and true or false
end

local WHITE = { 1, 1, 1 }
local RED   = { 1, 0.15, 0.15 }

local crossFrame
local function BuildCross()
    crossFrame = CreateFrame("Frame", "HKSuiteRangeCross", UIParent)
    crossFrame:SetSize(24, 24)
    crossFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    crossFrame:SetFrameStrata("MEDIUM")

    local hbar = crossFrame:CreateTexture(nil, "OVERLAY")
    hbar:SetTexture("Interface\\Buttons\\WHITE8X8")
    hbar:SetSize(22, 2)
    hbar:SetPoint("CENTER")

    local vbar = crossFrame:CreateTexture(nil, "OVERLAY")
    vbar:SetTexture("Interface\\Buttons\\WHITE8X8")
    vbar:SetSize(2, 22)
    vbar:SetPoint("CENTER")

    crossFrame.bars = { hbar, vbar }

    -- The frame must stay shown or its OnUpdate never fires; we toggle the bars.
    -- Only act on an actual change: the tracker spends most of its life disabled
    -- or without a target, and re-hiding already-hidden textures ten times a
    -- second is pure waste.
    local barsShown
    local function ShowBars(show)
        show = show and true or false
        if barsShown == show then return end
        barsShown = show
        for _, bar in ipairs(crossFrame.bars) do
            if show then bar:Show() else bar:Hide() end
        end
    end
    ShowBars(false)

    crossFrame:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.1 then return end
        self.elapsed = 0

        if not (enabled() and cfg.rangeTracker) then
            ShowBars(false)
            return
        end
        -- Only meaningful with a live, attackable target.
        if not UnitExists("target") or UnitIsDead("target")
            or not UnitCanAttack("player", "target") then
            ShowBars(false)
            return
        end

        ShowBars(true)
        local c = TargetInMeleeRange() and WHITE or RED
        for _, bar in ipairs(self.bars) do
            bar:SetVertexColor(c[1], c[2], c[3])
        end
    end)
end

-- ------------------------------------------------------------ trinket tracker
local SLOTS = { 13, 14 }   -- INVSLOT_TRINKET1 / INVSLOT_TRINKET2
local ICON = 36
local PAD, GAP = 4, 1

local trinketBox, icons

local function FormatTime(r)
    if r >= 60 then return math.floor(r / 60) .. "m" end
    return tostring(math.ceil(r))
end

-- Seconds left on a slot's cooldown, or nil when it's ready.
local function TrinketCooldown(slot)
    local start, duration, enable = GetInventoryItemCooldown("player", slot)
    if enable ~= 1 or not duration or duration <= 0 or not start or start <= 0 then return end
    local remaining = start + duration - GetTime()
    if remaining <= 0 then return end
    return remaining, start, duration
end

-- Desaturating is the "not ready yet" cue. A slight dim rides along with it, so
-- the state still reads on hardware that refuses to desaturate -- SetDesaturated
-- is a silent no-op there rather than an error. Guarded on the current state
-- because both the events and the ticker come through here.
local function SetIconReady(icon, ready)
    if icon.ready == ready then return end
    icon.ready = ready
    icon.texture:SetDesaturated(not ready and 1 or nil)
    local tint = ready and 1 or 0.7
    icon.texture:SetVertexColor(tint, tint, tint)
end

local function TickTrinkets(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.1 then return end
    self.elapsed = 0

    -- Deliberately no SetCooldown here: re-stamping it every tick restarts the
    -- sweep. The ticker exists to count the number down and to notice the moment
    -- a cooldown ends, which no event reliably reports.
    local ticking = false
    for i, slot in ipairs(SLOTS) do
        local icon = icons[i]
        if icon.texture:IsShown() then
            local remaining = TrinketCooldown(slot)
            if remaining then
                icon.text:SetText(cfg.trinketTimerText and FormatTime(remaining) or "")
                SetIconReady(icon, false)
                ticking = true
            else
                icon.text:SetText("")
                SetIconReady(icon, true)
            end
        end
    end

    -- Nothing left to count: stop until an event says a cooldown has started.
    if not ticking then self:SetScript("OnUpdate", nil) end
end

local function UpdateTrinkets()
    if not trinketBox then return end
    if not (enabled() and cfg.trinketTracker) then
        trinketBox:Hide()
        return
    end
    trinketBox:Show()

    local ticking = false
    for i, slot in ipairs(SLOTS) do
        local icon = icons[i]
        local tex = GetInventoryItemTexture("player", slot)
        if tex then
            icon.texture:SetTexture(tex)
            icon.texture:Show()
        else
            icon.texture:Hide()      -- empty slot: keep the frame (so the box stays draggable)
        end

        local remaining, start, duration = TrinketCooldown(slot)
        if tex and remaining then
            icon.cd:SetCooldown(start, duration)
            icon.text:SetText(cfg.trinketTimerText and FormatTime(remaining) or "")
            SetIconReady(icon, false)
            ticking = true
        else
            icon.cd:SetCooldown(0, 0)
            icon.text:SetText("")
            SetIconReady(icon, true)
        end
    end

    if ticking then
        trinketBox.elapsed = 0
        trinketBox:SetScript("OnUpdate", TickTrinkets)
    end
end

local function SavePosition()
    local point, _, relPoint, x, y = trinketBox:GetPoint()
    cfg.trinketPos = { point, relPoint, x, y }
end

local function BuildTrinketBox()
    local width = PAD * 2 + ICON * #SLOTS + GAP * (#SLOTS - 1)
    trinketBox = CreateFrame("Frame", "HKSuiteTrinketTracker", UIParent)
    trinketBox:SetSize(width, PAD * 2 + ICON)
    local p = cfg.trinketPos
    trinketBox:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or -160)
    trinketBox:SetFrameStrata("BACKGROUND")
    trinketBox:SetClampedToScreen(true)
    trinketBox:SetMovable(true)
    trinketBox:EnableMouse(true)
    trinketBox:RegisterForDrag("LeftButton")
    trinketBox:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() then self:StartMoving() end
    end)
    trinketBox:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    icons = {}
    for i = 1, #SLOTS do
        local holder = CreateFrame("Frame", nil, trinketBox)
        holder:SetSize(ICON, ICON)
        holder:SetPoint("LEFT", trinketBox, "LEFT", PAD + (i - 1) * (ICON + GAP), 0)
        holder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        holder:SetBackdropColor(0, 0, 0, 0.6)
        -- No mouse on the icons, so drags land on the parent box.

        local texture = holder:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", 2, -2)
        texture:SetPoint("BOTTOMRIGHT", -2, 2)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default icon border
        holder.texture = texture

        local cd = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
        cd:SetAllPoints(texture)
        holder.cd = cd

        local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("BOTTOM", 0, 2)
        holder.text = text

        icons[i] = holder
    end

    -- The ticker is attached only while something is actually on cooldown; see
    -- UpdateTrinkets. Nothing polls when both trinkets are ready.
    trinketBox:Hide()
end

-- ------------------------------------------------------------- stat display
-- A plain-text readout of the stats that matter, parked wherever you want it.
-- Ascension is classless, so which stats matter changes from build to build:
-- every line is its own toggle, and lines sitting at zero can drop out on their
-- own so a build only ever shows what it actually uses.
--
-- Every reader is guarded and returns nil when the client hasn't got the API
-- behind it -- a stat that can't be read simply isn't listed.
local STAT_PAD, STAT_GAP = 8, 14   -- label-to-value, and between entries in a row

local statBox, statLines, statsDirty

local function PrimaryStat(index)
    return function()
        if not UnitStat then return end
        local _, effective = UnitStat("player", index)
        return effective
    end
end

local function MeleeAttackPower()
    if not UnitAttackPower then return end
    local base, pos, neg = UnitAttackPower("player")
    if not base then return end
    return base + (pos or 0) + (neg or 0)
end

-- Spell power is per school; the paper doll shows the best of them, so do that.
local function BestBySchool(fn)
    if not fn then return end
    local best
    for school = 2, 7 do
        local value = fn(school)
        if value and (not best or value > best) then best = value end
    end
    return best
end

local function SpellPower()     return BestBySchool(GetSpellBonusDamage) end
local function SpellCrit()      return BestBySchool(GetSpellCritChance) end
local function MeleeCrit()      return GetCritChance and GetCritChance() end

-- Hit comes from rating plus whatever talents and gear add flat, which the
-- rating APIs don't include.
local function HitChance(ratingIndex, flatModifier)
    return function()
        if not GetCombatRatingBonus then return end
        local pct = GetCombatRatingBonus(ratingIndex) or 0
        if flatModifier and _G[flatModifier] then
            pct = pct + (_G[flatModifier]() or 0)
        end
        return pct
    end
end

local function Expertise()
    if not GetExpertise then return end
    return (GetExpertise())
end

-- One colour per stat, so a line is recognisable before you've read it. The spell
-- variants take their melee counterpart's colour; Stamina keeps the gold it wears
-- on the paper doll.
local RED    = { 0.90, 0.30, 0.30 }
local GREEN  = { 0.35, 0.85, 0.35 }
local BLUE   = { 0.35, 0.60, 1.00 }
local WHITE  = { 0.95, 0.95, 0.95 }
local ORANGE = { 1.00, 0.60, 0.20 }
local PURPLE = { 0.75, 0.45, 1.00 }
local GOLD   = { 1.00, 0.85, 0.30 }

local STATS = {
    { option = "statStr",       label = "Str",   color = RED,    read = PrimaryStat(1) },
    { option = "statAgi",       label = "Agi",   color = GREEN,  read = PrimaryStat(2) },
    { option = "statSta",       label = "Sta",   color = GOLD,   read = PrimaryStat(3) },
    { option = "statInt",       label = "Int",   color = BLUE,   read = PrimaryStat(4) },
    { option = "statSpi",       label = "Spi",   color = WHITE,  read = PrimaryStat(5) },
    { option = "statAP",        label = "AP",    color = RED,    read = MeleeAttackPower },
    { option = "statSP",        label = "SP",    color = BLUE,   read = SpellPower },
    { option = "statCrit",      label = "Crit",  color = GREEN,  read = MeleeCrit,  percent = true },
    { option = "statSpellCrit", label = "sCrit", color = GREEN,  read = SpellCrit,  percent = true },
    { option = "statHit",       label = "Hit",   color = ORANGE, read = HitChance(_G.CR_HIT_MELEE or 6, "GetHitModifier"), percent = true },
    { option = "statSpellHit",  label = "sHit",  color = ORANGE, read = HitChance(_G.CR_HIT_SPELL or 8, "GetSpellHitModifier"), percent = true },
    { option = "statExpertise", label = "Exp",   color = PURPLE, read = Expertise },
}

local function StatFont()
    local file = GameFontNormal:GetFont()
    return file, tonumber(cfg.statFontSize) or 12
end

local function GetStatLine(i)
    local line = statLines[i]
    if line then return line end

    line = CreateFrame("Frame", nil, statBox)
    line.label = line:CreateFontString(nil, "OVERLAY")
    line.label:SetJustifyH("LEFT")
    line.value = line:CreateFontString(nil, "OVERLAY")
    line.value:SetJustifyH("LEFT")
    -- A shadow, because this sits over whatever happens to be on screen.
    for _, fs in ipairs({ line.label, line.value }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end

    statLines[i] = line
    return line
end

local function FormatStat(def, value)
    if def.percent then return ("%.2f%%"):format(value) end
    return tostring(math.floor(value + 0.5))
end

local function UpdateStats()
    if not statBox then return end
    statsDirty = false

    if not (enabled() and cfg.statText) then
        statBox:Hide()
        return
    end

    statBox:EnableMouse(not cfg.statLocked)

    -- First pass: fill the lines in and measure them, since a vertical list wants
    -- one column width for every value and a row wants each entry's own width.
    local file, size = StatFont()
    local used, labelW, valueW = 0, 0, 0
    for _, def in ipairs(STATS) do
        if cfg[def.option] then
            local value = def.read()
            if value and (value ~= 0 or not cfg.statHideZero) then
                used = used + 1
                local line = GetStatLine(used)
                line.label:SetFont(file, size, "OUTLINE")
                line.value:SetFont(file, size, "OUTLINE")
                line.label:SetText(def.label)
                line.value:SetText(FormatStat(def, value))
                -- The value carries the stat's colour; the label a dimmer shade of
                -- it, so the two read as one entry.
                local r, g, b = unpack(def.color or WHITE)
                line.label:SetTextColor(r * 0.7, g * 0.7, b * 0.7)
                line.value:SetTextColor(r, g, b)
                line.labelW = math.ceil(line.label:GetStringWidth())
                line.valueW = math.ceil(line.value:GetStringWidth())
                labelW = math.max(labelW, line.labelW)
                valueW = math.max(valueW, line.valueW)
                line:Show()
            end
        end
    end
    for i = used + 1, #statLines do statLines[i]:Hide() end

    if used == 0 then
        statBox:Hide()
        return
    end

    local lineH = size + 4
    if cfg.statLayout == "horizontal" then
        local x = 0
        for i = 1, used do
            local line = statLines[i]
            local width = line.labelW + STAT_PAD + line.valueW
            line:ClearAllPoints()
            line:SetSize(width, lineH)
            line:SetPoint("LEFT", statBox, "LEFT", x, 0)
            line.label:ClearAllPoints()
            line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
            line.value:ClearAllPoints()
            line.value:SetPoint("LEFT", line, "LEFT", line.labelW + STAT_PAD, 0)
            x = x + width + STAT_GAP
        end
        statBox:SetSize(math.max(1, x - STAT_GAP), lineH)
    else
        -- Values share a right-aligned column so the numbers line up.
        local width = labelW + STAT_PAD + valueW
        for i = 1, used do
            local line = statLines[i]
            line:ClearAllPoints()
            line:SetSize(width, lineH)
            line:SetPoint("TOPLEFT", statBox, "TOPLEFT", 0, -(i - 1) * lineH)
            line.label:ClearAllPoints()
            line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
            line.value:ClearAllPoints()
            line.value:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        end
        statBox:SetSize(width, used * lineH)
    end

    statBox:Show()
end

local function SaveStatPosition()
    local point, _, relPoint, x, y = statBox:GetPoint()
    cfg.statPos = { point, relPoint, x, y }
end

local function BuildStatBox()
    statBox = CreateFrame("Frame", "HKSuiteStatText", UIParent)
    statBox:SetSize(80, 20)
    local p = cfg.statPos or {}
    statBox:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 220, p[4] or -160)
    statBox:SetFrameStrata("MEDIUM")
    statBox:SetClampedToScreen(true)
    statBox:SetMovable(true)
    statBox:RegisterForDrag("LeftButton")
    statBox:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() and not cfg.statLocked then self:StartMoving() end
    end)
    statBox:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveStatPosition()
    end)
    statBox:Hide()

    statLines = {}

    -- Stat changes arrive in bursts (an equip swap fires several of these at
    -- once), so events only mark the readout dirty and one redraw covers the lot.
    local ev = CreateFrame("Frame")
    for _, event in ipairs({
        "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER",
        "UNIT_ATTACK", "UNIT_AURA", "UNIT_LEVEL", "UNIT_RESISTANCES",
        "PLAYER_DAMAGE_DONE_MODS", "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
    }) do
        pcall(ev.RegisterEvent, ev, event)   -- not every build has every one
    end
    ev:SetScript("OnEvent", function(_, event, arg1)
        -- Unit events carry a unit token; PLAYER_EQUIPMENT_CHANGED carries a slot
        -- number, so only a string argument is a unit worth filtering on.
        if type(arg1) == "string" and arg1 ~= "player" then return end
        if enabled() and cfg.statText then statsDirty = true end
    end)

    statBox.ticker = CreateFrame("Frame")
    statBox.ticker:SetScript("OnUpdate", function(self, e)
        if not statsDirty then return end
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        UpdateStats()
    end)
end

-- --------------------------------------------------------------- loot rolls
-- A "Loot Rolls" section for the objectives tracker.
--
-- Group loot in 3.3.5 exposes the *item* being rolled (GetLootRollItemInfo) but
-- nothing about who has answered. The only source for that is the chat traffic
-- the server broadcasts to the group ("X has selected Need for: [item]"), so we
-- parse CHAT_MSG_LOOT. The patterns are built from the client's own GlobalStrings
-- rather than hardcoded English, and each capture is identified by its content
-- (item link / number / name) so the argument order in a translation can't break
-- them.
--
-- "Who is missing" is the group roster snapshotted when the roll started, minus
-- everyone who has answered. Players who cannot loot the item auto-pass, so they
-- resolve on their own; players out of the loot group simply never answer and
-- stay listed as waiting until the roll times out.
--
-- The section is one line per item: the top roll and how many of the group have
-- answered, rather than a row per player. The per-player breakdown moved into
-- the item's tooltip, which costs no space in the tracker.

local LR_PAD, LR_DEFAULT_W = 3, 204    -- LR_DEFAULT_W = WATCHFRAME_EXPANDEDWIDTH
local LR_TOGGLE_X = 0                  -- the header's +/- sits where a quest title starts
local LR_INDENT   = 13                 -- header text / item icon column, clear of the +/-

-- Roll choices, in the order group loot numbers them.
local VOTE = {
    [0] = { short = "Pass",  color = { 0.55, 0.55, 0.55 } },
    [1] = { short = "Need",  color = { 0.30, 1.00, 0.35 } },
    [2] = { short = "Greed", color = { 1.00, 0.82, 0.10 } },
    [3] = { short = "DE",    color = { 0.72, 0.45, 1.00 } },
}
local WAITING_COLOR = { 1.00, 0.55, 0.15 }
local DIM_COLOR     = { 0.45, 0.45, 0.45 }
-- The objectives frame's own palette: the gold it titles entries in, the brighter
-- gold it highlights them with, and the colour of an objective line.
local TITLE_COLOR     = { 0.75, 0.61, 0.00 }
local HIGHLIGHT_COLOR = { 1.00, 0.80, 0.10 }

local rolls    = {}   -- roll records, newest first
local rollByID = {}   -- live rollID -> record
local lootFrame, lrRows, lrHeader
local trackerCollapsed = false

local RefreshLootRolls   -- forward declaration (event handlers call it)

-- Loot traffic arrives in bursts: one roll in a 25-man is up to 25 chat lines of
-- choices and another 25 of roll numbers, and a boss drops several items at once.
-- Redrawing on each line meant a full relayout -- font probe, tracker measure, and
-- per-row text fitting -- several hundred times inside a couple of seconds, which
-- is what made looting stutter. Event handlers now only mark the section dirty and
-- the ticker redraws it at most four times a second. Anything you do yourself (the
-- header, a setting) still redraws on the spot.
local lrDirty = false
local function MarkLootRolls() lrDirty = true end

-- Turn a GlobalStrings format ("%s has selected Need for: %s") into a Lua
-- pattern. Placeholders go in as control bytes first so the (%d+) we inject for
-- a number can't be re-matched by the later %d pass.
local function BuildPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%%d%%%$s", "\1")     -- positional "%1$s"
    p = p:gsub("%%%d%%%$d", "\2")     -- positional "%1$d"
    p = p:gsub("%%s", "\1")
    p = p:gsub("%%d", "\2")
    p = p:gsub("\1", "(.+)")
    p = p:gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- Sort a pattern's captures by what they contain, not by position.
local function ParseCaps(...)
    local player, link, num
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then
            if v:find("|H", 1, true) then link = v
            elseif v:match("^%d+$") then num = tonumber(v)
            else player = v end
        end
    end
    return player, link, num
end

-- Message kinds we care about, most specific first: the auto-pass lines have to
-- be tested before the plain "passed on" line, which would otherwise swallow
-- them. `en` is only a fallback for a client missing the global.
local LOOT_MESSAGES = {
    { g = "LOOT_ROLL_PASSED_SELF_AUTO", en = "You automatically passed on: %s because you cannot loot that item.", vote = 0, me = true },
    { g = "LOOT_ROLL_PASSED_AUTO",        en = "%s automatically passed on: %s because he cannot loot that item.",  vote = 0 },
    { g = "LOOT_ROLL_PASSED_AUTO_FEMALE", en = "%s automatically passed on: %s because she cannot loot that item.", vote = 0 },
    { g = "LOOT_ROLL_PASSED_SELF",     en = "You passed on: %s",                     vote = 0, me = true },
    { g = "LOOT_ROLL_PASSED",          en = "%s passed on: %s",                      vote = 0 },
    { g = "LOOT_ROLL_NEED_SELF",       en = "You have selected Need for: %s",        vote = 1, me = true },
    { g = "LOOT_ROLL_NEED",            en = "%s has selected Need for: %s",          vote = 1 },
    { g = "LOOT_ROLL_GREED_SELF",      en = "You have selected Greed for: %s",       vote = 2, me = true },
    { g = "LOOT_ROLL_GREED",           en = "%s has selected Greed for: %s",         vote = 2 },
    { g = "LOOT_ROLL_DISENCHANT_SELF", en = "You have selected Disenchant for: %s",  vote = 3, me = true },
    { g = "LOOT_ROLL_DISENCHANT",      en = "%s has selected Disenchant for: %s",    vote = 3 },
    -- The rolled numbers arrive once the roll closes. No English fallback: the
    -- wording varies between builds and the section reads fine without them.
    { g = "LOOT_ROLL_ROLLED_NEED", vote = 1, rolled = true },
    { g = "LOOT_ROLL_ROLLED_GREED", vote = 2, rolled = true },
    { g = "LOOT_ROLL_ROLLED_DE",   vote = 3, rolled = true },
    { g = "LOOT_ROLL_ALL_PASSED",  allPassed = true },
    -- Who actually walked away with it.
    { g = "LOOT_ITEM_SELF_MULTIPLE", won = true, me = true },
    { g = "LOOT_ITEM_SELF",          won = true, me = true },
    { g = "LOOT_ITEM_MULTIPLE",      won = true },
    { g = "LOOT_ITEM",               won = true },
}

local function CompileLootPatterns()
    for _, m in ipairs(LOOT_MESSAGES) do
        m.pattern = BuildPattern(_G[m.g] or m.en)
    end
end

-- ---------------------------------------------------------------- group data
local function RaidSize()  return (GetNumRaidMembers  and GetNumRaidMembers()  or 0) end
local function PartySize() return (GetNumPartyMembers and GetNumPartyMembers() or 0) end

local function GroupRoster()
    local names, classes = {}, {}
    local function add(unit)
        local n = UnitName(unit)
        if n and n ~= UNKNOWNOBJECT then
            names[#names + 1] = n
            classes[n] = select(2, UnitClass(unit))
        end
    end
    local raid = RaidSize()
    if raid > 0 then
        for i = 1, raid do add("raid" .. i) end
    else
        add("player")
        for i = 1, PartySize() do add("party" .. i) end
    end
    return names, classes
end

local function LookupClass(name)
    local raid = RaidSize()
    if raid > 0 then
        for i = 1, raid do
            if UnitName("raid" .. i) == name then return select(2, UnitClass("raid" .. i)) end
        end
    else
        if UnitName("player") == name then return select(2, UnitClass("player")) end
        for i = 1, PartySize() do
            if UnitName("party" .. i) == name then return select(2, UnitClass("party" .. i)) end
        end
    end
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- ------------------------------------------------------------- roll records
local function ItemKey(link)
    return link and link:match("item:(%d+)")
end

-- Locate the roll a chat line refers to. Prefers a still-open roll the player
-- hasn't answered yet, so two simultaneous rolls of the same item fill in turn.
local function FindRoll(link, playerName, anyState)
    if not link then return end
    local key, name = ItemKey(link), link:match("%[(.-)%]")
    local fallback
    for _, r in ipairs(rolls) do
        if (key and r.key == key) or (name and r.name == name) then
            if not anyState and not r.finished
                and (playerName == nil or r.votes[playerName] == nil) then
                return r
            end
            fallback = fallback or r
        end
    end
    return fallback
end

local function Responded(rec)
    local n = 0
    for _ in pairs(rec.votes) do n = n + 1 end
    return n
end

local function Finish(rec)
    if not rec.finished then
        rec.finished = GetTime()
        if rec.rollID then rollByID[rec.rollID] = nil end
    end
end

local function CheckComplete(rec)
    for _, name in ipairs(rec.candidates) do
        if rec.votes[name] == nil then return end
    end
    Finish(rec)
end

-- Group loot awards to the highest Need roll if there is one, else the highest
-- Greed/Disenchant roll -- so that's how we pick the winner from the numbers.
-- On a roll that is still open this is the current leader: whoever would take the
-- item if it closed now. (3.3.5 normally broadcasts the numbers only as the roll
-- closes, so an open roll usually has none yet and this returns nothing.)
local function TopRoll(rec)
    if rec.wonBy then return rec.wonBy, rec.rollNums[rec.wonBy] end
    local bestName, bestNum, bestNeed
    for name, num in pairs(rec.rollNums) do
        local need = (rec.votes[name] == 1)
        if bestName == nil or (need and not bestNeed)
            or (need == bestNeed and num > bestNum) then
            bestName, bestNum, bestNeed = name, num, need
        end
    end
    return bestName, bestNum
end

local function TrimRolls()
    local keep = math.max(1, tonumber(cfg.lootRollsMax) or 5) * 3
    for i = #rolls, keep + 1, -1 do
        local rec = rolls[i]
        if rec.rollID then rollByID[rec.rollID] = nil end
        table.remove(rolls, i)
    end
end

local function StartRoll(rollID, rollTime)
    local texture, name, count, quality, bop = GetLootRollItemInfo(rollID)
    if not name then return end
    local link = GetLootRollItemLink(rollID)
    local names, classes = GroupRoster()
    local rec = {
        rollID = rollID, link = link, name = name, texture = texture,
        count = count or 1, quality = quality or 1, bop = bop,
        key = ItemKey(link),
        started = GetTime(),
        deadline = GetTime() + ((tonumber(rollTime) or 60000) / 1000),
        candidates = names, classes = classes,
        votes = {}, order = {}, rollNums = {},
    }
    table.insert(rolls, 1, rec)
    rollByID[rollID] = rec
    TrimRolls()
    MarkLootRolls()
end

-- Character names never contain a space, so a captured "name" that does means we
-- matched a broader message than we meant to (e.g. an auto-pass line falling
-- through to the plain "passed on" pattern). Drop it rather than invent a player.
local function ValidName(name)
    return name and name ~= "" and not name:find("%s")
end

local function RecordVote(link, playerName, vote)
    if not ValidName(playerName) then return end
    local rec = FindRoll(link, playerName)
    if not rec then return end
    if rec.votes[playerName] == nil then
        rec.order[#rec.order + 1] = playerName
        local known
        for _, n in ipairs(rec.candidates) do
            if n == playerName then known = true break end
        end
        if not known then rec.candidates[#rec.candidates + 1] = playerName end
        rec.classes[playerName] = rec.classes[playerName] or LookupClass(playerName)
    end
    rec.votes[playerName] = vote
    CheckComplete(rec)
    MarkLootRolls()
end

local function RecordRolled(link, playerName, num, vote)
    if not (ValidName(playerName) and num) then return end
    local rec = FindRoll(link, nil, true)
    if not rec then return end
    if rec.votes[playerName] == nil then RecordVote(link, playerName, vote) end
    rec.rollNums[playerName] = num
    Finish(rec)
    MarkLootRolls()
end

local function RecordWinner(link, playerName)
    local rec = FindRoll(link, nil, true)
    -- Only a roll that just closed; otherwise ordinary looting of the same item
    -- id later on would rewrite the result.
    if not rec or not rec.finished or rec.wonBy then return end
    if GetTime() - rec.finished > 20 then return end
    rec.wonBy = playerName
    MarkLootRolls()
end

local function HandleLootMessage(msg)
    if not msg then return end
    for _, m in ipairs(LOOT_MESSAGES) do
        if m.pattern then
            local a, b, c = msg:match(m.pattern)
            if a then
                local player, link, num = ParseCaps(a, b, c)
                if m.me then player = UnitName("player") end
                if m.allPassed then
                    local rec = FindRoll(link, nil, true)
                    if rec then rec.allPassed = true; Finish(rec); MarkLootRolls() end
                elseif m.won then
                    RecordWinner(link, player)
                elseif m.rolled then
                    RecordRolled(link, player, num, m.vote)
                elseif player then
                    RecordVote(link, player, m.vote)
                end
                return
            end
        end
    end
end

-- ------------------------------------------------------------- tracker look
-- The section is meant to read as one more block of the objectives frame, so it
-- borrows the frame's own metrics and font rather than picking its own. The font
-- is read off a live tracker line, which means whatever restyled the tracker
-- (ElvUI, the client's own objectives font) carries over for free.
local function TrackerLineHeight()
    local h = tonumber(_G.WATCHFRAME_LINEHEIGHT)
    if h and h >= 8 then return h end
    return 16
end

local function TrackerBlockGap()
    local g = tonumber(_G.WATCHFRAME_TYPE_OFFSET)
    if g and g >= 0 then return g end
    return 10
end

local function PoolFont(pool)
    local line = type(pool) == "table" and pool[1]
    if line and line.text then
        local file, size, flags = line.text:GetFont()
        if file then return file, size, flags end
    end
end

local function TrackerFont()
    local file, size, flags = PoolFont(_G.WATCHFRAME_QUESTLINES)
    if not file then file, size, flags = PoolFont(_G.WATCHFRAME_ACHIEVEMENTLINES) end
    if file then return file, size, flags end
    return GameFontHighlight:GetFont()      -- nothing tracked yet
end

local lrFontFile, lrFontSize, lrFontFlags

local function SetRowFont(fs)
    if fs and lrFontFile then fs:SetFont(lrFontFile, lrFontSize, lrFontFlags) end
end

local function ApplyTrackerFont(row)
    SetRowFont(row.left)
    SetRowFont(row.right)
end

-- Re-reads the tracker's font and pushes it onto the section. A no-op unless
-- something restyled the tracker since the last refresh.
local function RefreshTrackerFont()
    local file, size, flags = TrackerFont()
    if not file then return end
    if file == lrFontFile and size == lrFontSize and flags == lrFontFlags then return end
    lrFontFile, lrFontSize, lrFontFlags = file, size, flags
    if lrHeader then SetRowFont(lrHeader.text) end
    if lrRows then
        for _, row in ipairs(lrRows) do ApplyTrackerFont(row) end
    end
end

-- ElvUI swaps the tracker's collapse button for its own square +/-; match it when
-- it's there so our section doesn't stand out.
local function ToggleTexture(expanded)
    local E = _G.ElvUI and _G.ElvUI[1]
    local media = E and E.Media and E.Media.Textures
    if media and media.MinusButton and media.PlusButton then
        return expanded and media.MinusButton or media.PlusButton
    end
    return expanded and "Interface\\Buttons\\UI-MinusButton-Up"
                     or "Interface\\Buttons\\UI-PlusButton-Up"
end

-- ------------------------------------------------------------------ display
-- FontStrings in 3.3.5 wrap instead of eliding, so trim to fit by hand.
--
-- Every probe is a SetText plus a GetStringWidth, and each of those makes the
-- client lay the string out again -- so dropping one character at a time cost
-- twenty-odd layouts per row that needed trimming, on every redraw. Halving the
-- range gets there in about five, and a name that already fits (the common case)
-- costs one.
local function SetTruncated(fs, text, maxWidth)
    text = text or ""
    fs:SetText(text)
    if not maxWidth or maxWidth <= 0 then return end
    if fs:GetStringWidth() <= maxWidth then return end

    local lo, hi, best = 1, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        -- Never cut inside a multi-byte character, or the tail renders as junk.
        -- The bounds still move by `mid`, so backing the cut up can't stall the
        -- search; it only ever settles a character or two short.
        local cut = mid
        while cut > 1 do
            local nextByte = text:byte(cut + 1)
            if not nextByte or nextByte < 0x80 or nextByte > 0xBF then break end
            cut = cut - 1
        end
        local candidate = text:sub(1, cut) .. "..."
        fs:SetText(candidate)
        if fs:GetStringWidth() <= maxWidth then
            best = candidate
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    fs:SetText(best)
end

-- The tracker highlights an entry by turning its title gold rather than by
-- painting a bar behind it, so that's what a hovered item row does too.
-- Everyone who answered, in the order they did, then anyone still to roll. This
-- is the detail the expandable player rows used to carry.
local function AddRollLines(rec)
    if not rec then return end
    GameTooltip:AddLine(" ")
    local seen = {}
    for _, name in ipairs(rec.order) do
        if not seen[name] then
            seen[name] = true
            local v = VOTE[rec.votes[name]] or VOTE[0]
            local num = rec.rollNums[name]
            local r, g, b = ClassColor(rec.classes[name])
            GameTooltip:AddDoubleLine(name, num and (v.short .. " " .. num) or v.short,
                r, g, b, v.color[1], v.color[2], v.color[3])
        end
    end
    if rec.finished then return end
    for _, name in ipairs(rec.candidates) do
        if rec.votes[name] == nil then
            GameTooltip:AddDoubleLine(name, "waiting",
                DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3],
                WAITING_COLOR[1], WAITING_COLOR[2], WAITING_COLOR[3])
        end
    end
end

local function RowOnEnter(self)
    self.left:SetTextColor(unpack(HIGHLIGHT_COLOR))
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.link)
    AddRollLines(self.rec)
    GameTooltip:Show()
end

local function RowOnLeave(self)
    if self.baseR then self.left:SetTextColor(self.baseR, self.baseG, self.baseB) end
    GameTooltip:Hide()
end

local function RowOnClick(self)
    local rec = self.rec
    if not (rec and rec.link) then return end
    if IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(rec.link)
    elseif IsControlKeyDown() and DressUpItemLink then
        DressUpItemLink(rec.link)
    end
end

local function GetRow(i)
    local row = lrRows[i]
    if row then return row end

    row = CreateFrame("Button", nil, lootFrame)
    row:SetPoint("LEFT", lootFrame, "LEFT", 0, 0)
    row:SetPoint("RIGHT", lootFrame, "RIGHT", 0, 0)

    -- The icon sits in the column the header's text starts in, so items read as
    -- entries under the header the way quest titles do in the tracker.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", LR_INDENT, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The font object is only a starting point -- ApplyTrackerFont swaps in
    -- whatever the tracker is using.
    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.left:SetJustifyH("LEFT")

    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)

    lrRows[i] = row
    ApplyTrackerFont(row)
    return row
end

-- The right column carries the whole state of the roll in one line:
--   open, no numbers yet   "3/5  38s"      answered out of the group, time left
--   numbers in, still open "Bob 87  3/5"   who leads, and the progress
--   closed                 "Bob 87"        the winning roll
local function RightText(rec)
    if rec.allPassed then
        return "all passed", DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3]
    end
    local progress = Responded(rec) .. "/" .. #rec.candidates
    local top, num = TopRoll(rec)
    if top then
        local text = num and (top .. " " .. num) or top
        if not rec.finished then text = text .. "  " .. progress end
        local r, g, b = ClassColor(rec.classes[top] or LookupClass(top))
        return text, r, g, b
    end
    if rec.finished then
        return "done", DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3]
    end
    local left = math.max(0, math.ceil(rec.deadline - GetTime()))
    return progress .. "  " .. left .. "s",
        WAITING_COLOR[1], WAITING_COLOR[2], WAITING_COLOR[3]
end

local function LayoutItemRow(row, rec, y, width)
    local lineH = TrackerLineHeight()
    row:SetHeight(lineH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", lootFrame, "TOPRIGHT", 0, y)
    row.rec, row.link = rec, rec.link
    row:EnableMouse(true)

    local iconSize = lineH - 4
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetTexture(rec.texture)
    row.icon:Show()

    local rightText, rc, rg, rb = RightText(rec)
    row.right:SetText(rightText)
    row.right:SetTextColor(rc, rg, rb)

    local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rec.quality]
    row.baseR, row.baseG, row.baseB = q and q.r or 1, q and q.g or 1, q and q.b or 1
    row.left:SetTextColor(row.baseR, row.baseG, row.baseB)
    local indent = LR_INDENT + iconSize + 3
    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row, "LEFT", indent, 0)
    local label = rec.count > 1 and (rec.count .. "x " .. rec.name) or rec.name
    SetTruncated(row.left, label, width - indent - row.right:GetStringWidth() - 6)
end

-- Which rolls the section bothers with. Need-only is the default: a roll you
-- passed or greeded resolves without you, so watching it is noise -- what you want
-- on screen is whether the thing you actually asked for is coming your way. Note
-- an item only appears once you've answered Need on it.
local function IsRelevant(rec, me)
    if not cfg.lootRollsNeedOnly then return true end
    return me ~= nil and rec.votes[me] == 1        -- 1 = Need
end

-- Newest first, so the first match is the newest relevant roll. Kept allocation-
-- free because the ticker asks four times a second.
local function NewestRelevantRoll()
    local me = UnitName("player")
    for _, rec in ipairs(rolls) do
        if IsRelevant(rec, me) then return rec end
    end
end

local function VisibleRolls()
    local max = math.max(1, tonumber(cfg.lootRollsMax) or 5)
    local me = UnitName("player")
    local list = {}
    for _, rec in ipairs(rolls) do
        if IsRelevant(rec, me) then
            list[#list + 1] = rec
            if #list >= max then break end
        end
    end
    return list
end

local function ShouldShow()
    if not (enabled() and cfg.lootRolls) then return false end
    if trackerCollapsed and cfg.lootRollsAttach then return false end
    local newest = NewestRelevantRoll()
    if not newest then return false end
    local hideAfter = tonumber(cfg.lootRollsHideAfter) or 0
    if hideAfter > 0 then
        if newest.finished and (GetTime() - newest.finished) > hideAfter then return false end
    end
    return true
end

-- --------------------------------------------------- sitting under the quests
-- The tracker lays its blocks out top-down inside WatchFrameLines, each line
-- anchored to the one above it, so the bottom of the list is simply the lowest
-- line still shown. We measure that rather than trusting WatchFrame.nextOffset:
-- the quest limit below hides trailing lines after the layout has run, and that
-- offset would still count them.
local LINE_POOLS = { "WATCHFRAME_QUESTLINES", "WATCHFRAME_ACHIEVEMENTLINES", "WATCHFRAME_TIMERLINES" }

local function TrackerContentOffset()
    local lines = _G.WatchFrameLines
    local top = lines and lines:GetTop()
    if not top then return end
    local lowest
    for _, key in ipairs(LINE_POOLS) do
        local pool = _G[key]
        if type(pool) == "table" then
            for _, line in ipairs(pool) do
                if line:IsShown() then
                    local bottom = line:GetBottom()
                    if bottom and (not lowest or bottom < lowest) then lowest = bottom end
                end
            end
        end
    end
    if not lowest then return 0 end     -- nothing tracked: start where the lines would
    return lowest - top - TrackerBlockGap()
end

-- What the last call actually committed. Re-anchoring invalidates the frame's
-- layout and every row inside it, and this runs from the tracker's own update hook
-- as well as from each redraw -- so a placement that hasn't moved is skipped.
local placedAttached, placedOffset, placedWidth, placedLevel

local function ApplyPlacement()
    if not lootFrame then return end
    local lines = _G.WatchFrameLines
    local attach = cfg.lootRollsAttach and lines
    local offset = attach and TrackerContentOffset()
    -- Attached but the tracker hasn't a valid rectangle yet (early login): leave the
    -- section where it is rather than flinging it to the free-floating position.
    if attach and not offset then return end

    if offset then
        local w = lines:GetWidth()
        if not w or w < 60 then w = LR_DEFAULT_W end
        -- The tracker's frame level is part of the key: something restyling the
        -- tracker can move it without the offset or width changing, and we'd end up
        -- drawing behind it.
        local level = lines:GetFrameLevel()
        if placedAttached and placedOffset == offset and placedWidth == w
            and placedLevel == level and lootFrame:GetParent() == lines then
            return
        end
        placedAttached, placedOffset, placedWidth, placedLevel = true, offset, w, level

        lootFrame:ClearAllPoints()
        -- Parented to the tracker's line frame so we inherit its scale and go with
        -- it when something hides the whole tracker (ElvUI's boss-fight auto-hide).
        if lootFrame:GetParent() ~= lines then lootFrame:SetParent(lines) end
        lootFrame:SetWidth(w)
        lootFrame:SetPoint("TOPLEFT", lines, "TOPLEFT", 0, offset)
        lootFrame:SetFrameStrata(lines:GetFrameStrata())
        lootFrame:SetFrameLevel(level + 5)
        lootFrame:EnableMouse(false)
    else
        if placedAttached == false and lootFrame:GetParent() == UIParent then return end
        placedAttached, placedOffset, placedWidth, placedLevel = false, nil, nil, nil

        lootFrame:ClearAllPoints()
        if lootFrame:GetParent() ~= UIParent then lootFrame:SetParent(UIParent) end
        lootFrame:SetWidth(LR_DEFAULT_W)
        local p = cfg.lootRollsPos or {}
        lootFrame:SetPoint(p[1] or "TOPRIGHT", UIParent, p[2] or "TOPRIGHT", p[3] or -220, p[4] or -260)
        lootFrame:SetFrameStrata("MEDIUM")
        lootFrame:EnableMouse(true)
    end
end

-- ---------------------------------------------------------------- quest limit
-- Pinned under the quests, the section drifts down the screen with every extra
-- quest you track, so cap how many the tracker draws. Blizzard draws quests last
-- (timers, then achievements, then quests), which means hiding the trailing ones
-- leaves no hole behind. We hide them after the layout has run rather than
-- shortening the layout itself: the tracker's quest-item buttons are protected,
-- and code of ours running inside Blizzard's layout would taint them.
local hiddenLines = {}

local function QuestLimit()
    if not (enabled() and cfg.lootRolls and cfg.lootRollsAttach and cfg.lootRollsLimitQuests) then
        return
    end
    local n = tonumber(cfg.lootRollsQuestLimit) or 0
    if n >= 1 then return n end
end

local function LimitTrackerQuests()
    local buttons, lines = _G.WATCHFRAME_LINKBUTTONS, _G.WatchFrameLines
    if type(buttons) ~= "table" or not lines then return end

    for line in pairs(hiddenLines) do hiddenLines[line] = nil end

    local limit, shown = QuestLimit(), 0
    if limit then
        for _, button in ipairs(buttons) do
            if button:IsShown() and button.type == "QUEST"
                and button.lines and button.startLine and button.lastLine then
                shown = shown + 1
                if shown > limit then
                    button:Hide()
                    for i = button.startLine, button.lastLine do
                        local line = button.lines[i]
                        if line then
                            line:Hide()
                            hiddenLines[line] = true
                        end
                    end
                end
            end
        end
    end
    if not next(hiddenLines) then return end

    -- A quest's item button and its map POI icon are anchored to its title line,
    -- so anything hanging off a line we just hid goes with it.
    --
    -- GetChildren() returns the whole list every call, so asking for it inside the
    -- loop copied every child once per child. Fetch it once instead: this runs on
    -- every WatchFrame_Update, which the tracker fires on any objective change.
    local children = { lines:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child:IsShown() and child:GetNumPoints() > 0 then
            local _, relative = child:GetPoint(1)
            if relative and hiddenLines[relative] then child:Hide() end
        end
    end
end

-- Make the tracker lay itself out again after a settings change. Never mid-fight:
-- its quest-item buttons are protected and poking the layout risks blocking them.
local function RelayoutTracker()
    if type(_G.WatchFrame_Update) == "function" and not InCombatLockdown() then
        WatchFrame_Update()
    end
    RefreshLootRolls()
end

function RefreshLootRolls()
    if not lootFrame then return end

    if not ShouldShow() then
        lootFrame:Hide()
        return
    end

    RefreshTrackerFont()
    ApplyPlacement()
    local lineH = TrackerLineHeight()
    local width = lootFrame:GetWidth()
    local visible = VisibleRolls()

    local pending = 0
    for _, rec in ipairs(visible) do
        if not rec.finished then pending = pending + 1 end
    end
    lrHeader:SetHeight(lineH)
    lrHeader.toggle:SetSize(lineH - 4, lineH - 4)
    lrHeader.text:SetText(pending > 0 and ("Loot Rolls (" .. pending .. ")") or "Loot Rolls")
    lrHeader.toggle:SetTexture(ToggleTexture(not cfg.lootRollsCollapsed))

    local used, y = 0, -lineH
    if cfg.lootRollsCollapsed then
        for _, row in ipairs(lrRows) do row:Hide() end
    else
        for _, rec in ipairs(visible) do
            used = used + 1
            local row = GetRow(used)
            LayoutItemRow(row, rec, y, width)
            row:Show()
            y = y - lineH
        end
        for i = used + 1, #lrRows do lrRows[i]:Hide() end
    end

    lootFrame:SetHeight(math.max(lineH, -y + LR_PAD))
    lootFrame:Show()
end

local function SaveLootRollsPosition()
    local point, _, relPoint, x, y = lootFrame:GetPoint()
    cfg.lootRollsPos = { point, relPoint, x, y }
end

local function BuildLootRollsFrame()
    lootFrame = CreateFrame("Frame", "HKSuiteLootRolls", UIParent)
    lootFrame:SetSize(LR_DEFAULT_W, TrackerLineHeight())
    local p = cfg.lootRollsPos or {}
    lootFrame:SetPoint(p[1] or "TOPRIGHT", UIParent, p[2] or "TOPRIGHT", p[3] or -220, p[4] or -260)
    lootFrame:SetMovable(true)
    lootFrame:RegisterForDrag("LeftButton")
    lootFrame:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() and not cfg.lootRollsAttach then self:StartMoving() end
    end)
    lootFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveLootRollsPosition()
    end)
    lootFrame:Hide()

    lrRows = {}

    -- Styled like one of the tracker's own entry titles: same font, same gold, and
    -- the same brighter gold on hover.
    lrHeader = CreateFrame("Button", nil, lootFrame)
    lrHeader:SetHeight(TrackerLineHeight())
    lrHeader:SetPoint("TOPLEFT", 0, 0)
    lrHeader:SetPoint("TOPRIGHT", 0, 0)
    lrHeader.toggle = lrHeader:CreateTexture(nil, "ARTWORK")
    lrHeader.toggle:SetPoint("LEFT", LR_TOGGLE_X, 0)
    lrHeader.text = lrHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lrHeader.text:SetPoint("LEFT", LR_INDENT, 0)
    lrHeader.text:SetTextColor(unpack(TITLE_COLOR))
    lrHeader:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(HIGHLIGHT_COLOR)) end)
    lrHeader:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(TITLE_COLOR)) end)
    lrHeader:SetScript("OnClick", function()
        cfg.lootRollsCollapsed = not cfg.lootRollsCollapsed
        RefreshLootRolls()
    end)
    RefreshTrackerFont()

    if _G.WatchFrame then
        -- The tracker relays out constantly (quest progress, collapse, width); the
        -- quest limit and our own anchor both hang off the end of that.
        if type(WatchFrame_Update) == "function" then
            hooksecurefunc("WatchFrame_Update", function()
                LimitTrackerQuests()
                if lootFrame:IsShown() then ApplyPlacement() end
            end)
        end
        if type(WatchFrame_Collapse) == "function" then
            hooksecurefunc("WatchFrame_Collapse", function()
                trackerCollapsed = true
                RefreshLootRolls()
            end)
        end
        if type(WatchFrame_Expand) == "function" then
            hooksecurefunc("WatchFrame_Expand", function()
                trackerCollapsed = false
                RefreshLootRolls()
            end)
        end
    end

    -- Drives the countdown, closes rolls nobody answered, and hides the section
    -- once it has gone stale (or the module was switched off in the settings).
    -- Nothing here can matter until a roll has actually been recorded, so the
    -- common case -- feature off, or simply not in a group -- costs one table
    -- length check.
    lootFrame.ticker = CreateFrame("Frame")
    lootFrame.ticker:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        if #rolls == 0 then lrDirty = false return end

        local now = GetTime()
        local dirty, pending = lrDirty, false
        for _, rec in ipairs(rolls) do
            if not rec.finished then
                if now >= rec.deadline then
                    Finish(rec)
                    dirty = true
                else
                    pending = true
                end
            end
        end
        -- The countdown only needs redrawing once a second.
        local sec = math.floor(now)
        if pending and sec ~= self.lastSec then
            self.lastSec = sec
            dirty = true
        end
        -- IsShown() is 1/nil here, so normalise before comparing.
        local shown = lootFrame:IsShown() and true or false
        if dirty or shown ~= ShouldShow() then
            lrDirty = false
            RefreshLootRolls()
        end
    end)
end

-- -------------------------------------------------------------- path reminder
-- An Ascension character picks a Path, which is the primary stat it scales with:
-- Strength, Agility, Intelligence, Healing or Duality. Forgetting to set one is
-- easy and costs you the scaling, so this puts a warning over your character
-- until a Path is applied.
--
-- The character sheet's own Path line is the source for how to read it -- see
-- ElvUI_Enhanced's Modules/Blizzard/CharacterFrame.lua PrimaryStat(), which does
--     local statID = C_PrimaryStat:GetActivePrimaryStat()
--     local _, _, _, name = C_PrimaryStat:GetPrimaryStatInfo(statID)
-- and prints "No Primary Stat" when statID comes back empty. Both are methods on
-- the C_PrimaryStat table, so they take the table as self.
--
-- A client without C_PrimaryStat has no Paths to be missing, so an absent API
-- means "can't tell" and the reminder stays quiet rather than warning forever.
local PATH_NAME_RETURN = 4   -- GetPrimaryStatInfo -> spellID, ?, icon, name, tooltip

-- Returns: hasPath, pathName, supported
local function ActivePath()
    local api = _G.C_PrimaryStat
    if type(api) ~= "table" or type(api.GetActivePrimaryStat) ~= "function" then
        return false, nil, false
    end
    local ok, id = pcall(api.GetActivePrimaryStat, api)
    if not ok then return false, nil, false end
    -- Empty means no Path. Nil is what the character sheet checks for; 0 is
    -- covered too, in case the server ever answers that way instead.
    if not id or id == 0 then return false, nil, true end

    local name
    if type(api.GetPrimaryStatInfo) == "function" then
        local res = { pcall(api.GetPrimaryStatInfo, api, id) }
        if res[1] then name = res[1 + PATH_NAME_RETURN] end
    end
    -- A Path whose name won't resolve is still a Path, so don't warn about it.
    return true, name, true
end

local pathFrame

local function UpdatePathReminder()
    if not pathFrame then return end
    if not (enabled() and cfg.pathReminder) then
        pathFrame:Hide()
        return
    end
    local hasPath, _, supported = ActivePath()
    if hasPath or not supported then
        pathFrame:Hide()
        return
    end

    local file = GameFontNormal:GetFont()
    local size = tonumber(cfg.pathReminderSize) or 18
    pathFrame.text:SetFont(file, size, "OUTLINE")
    local text = cfg.pathReminderText
    if not text or text == "" then text = ns.defaults.uifeatures.pathReminderText end
    pathFrame.text:SetText(text)
    pathFrame:ClearAllPoints()
    pathFrame:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(cfg.pathReminderY) or 100)
    pathFrame:Show()
end

local function BuildPathReminder()
    pathFrame = CreateFrame("Frame", "HKSuitePathReminder", UIParent)
    pathFrame:SetSize(1, 1)                 -- the text sizes itself
    pathFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    pathFrame:SetFrameStrata("MEDIUM")
    pathFrame:Hide()

    pathFrame.text = pathFrame:CreateFontString(nil, "OVERLAY")
    pathFrame.text:SetPoint("CENTER")
    pathFrame.text:SetTextColor(unpack(RED))
    pathFrame.text:SetShadowOffset(1, -1)    -- it sits over the world
    pathFrame.text:SetShadowColor(0, 0, 0, 1)

    -- A Path is set once, at an NPC, and there's no event for it -- and the
    -- Overview's module switch doesn't notify modules either. Both are covered by
    -- re-checking on a slow tick; it's two API calls a second.
    local poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 1 then return end
        self.elapsed = 0
        UpdatePathReminder()
    end)
end

-- ------------------------------------------------------------------- options
function M:BuildSettings(page)
    page:Header("In-range tracker")
    page:Check({
        label = "Enable in-range tracker",
        tooltip = "Shows a crosshair over your character: white when your target is in melee range, red when out of range.",
        get = function() return cfg.rangeTracker end,
        set = function(v) cfg.rangeTracker = v end,
    })

    local saved
    local function SavedText()
        local v = cfg.rangeSpell
        if v and v ~= "" then return "Using: |cff00ff00" .. v .. "|r" end
        return "Using: |cffaaaaaa(auto-detected from the melee abilities you know)|r"
    end

    local spell = page:Input({
        label = "Melee ability for the range check (optional)",
        name = "HKSuiteRangeSpellBox", width = 220,
        tooltip = "Ascension is classless, so with this blank the tracker probes a list of real "
            .. "5-yard melee abilities and uses whichever one you actually know.",
        get = function() return cfg.rangeSpell or "" end,
        set = function(v)
            cfg.rangeSpell = v
            InvalidateMeleeSpell()          -- force a re-resolve with the new preference
        end,
        onChange = function() if saved then saved:SetText(SavedText()) end end,
    })

    saved = page:Hint(SavedText())

    -- Setting it from the last ability you cast is the reliable route: the
    -- spellbook can't be open while these settings are, so shift-clicking a spell
    -- into the box usually isn't possible.
    page:Button({
        text = "Set from last-used ability", width = 220,
        tooltip = "Cast your melee ability once, then click this.",
        onClick = function()
            if lastCastSpell and lastCastSpell ~= "" then
                cfg.rangeSpell = lastCastSpell
                InvalidateMeleeSpell()
                spell:Refresh()
                saved:SetText(SavedText())
                ns.Print("Range ability set to: " .. lastCastSpell)
            else
                ns.Print("Cast your melee ability once, then click 'Set from last-used ability'.")
            end
        end,
    })

    -- Now that settings live in their own window the spellbook can be open at the
    -- same time, so shift-clicking a spell into the box finally works.
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and spell.box:HasFocus() then
            cfg.rangeSpell = tostring(link):match("%[(.-)%]") or tostring(link)
            InvalidateMeleeSpell()
            spell:Refresh()
            saved:SetText(SavedText())
        end
    end)

    page:OnRefresh(function() saved:SetText(SavedText()) end)

    page:Header("Trinket tracker")
    local trinkets = page:Check({
        label = "Enable trinket tracker",
        tooltip = "Shows your equipped trinkets and their cooldowns in a box.",
        get = function() return cfg.trinketTracker end,
        set = function(v) cfg.trinketTracker = v end,
        onChange = UpdateTrinkets,
    })

    trinkets:BindChildren({
        page:Check({
            label = "Show the countdown number", indent = true,
            tooltip = "The number counting down over the icon. Off, the cooldown sweep is still "
                .. "there -- useful if you already run an addon that puts a timer on cooldowns.",
            get = function() return cfg.trinketTimerText end,
            set = function(v) cfg.trinketTimerText = v end,
            onChange = UpdateTrinkets,
        }),
    })

    page:Hint("Hold Ctrl and left-drag the trinket box to reposition it.")

    page:Section({
        title = "Stat display",
        tooltip = "A movable text readout of the stats ticked below.",
        get = function() return cfg.statText end,
        set = function(v) cfg.statText = v end,
        onChange = UpdateStats,
    })
    page:Text("Shows your stats as plain text on screen, each in its own colour. Tick the ones you "
        .. "want -- Ascension is classless, so the useful set changes with the build. Hold Ctrl and "
        .. "left-drag to move it.")

    local STAT_LABELS = {
        { option = "statStr",       label = "Strength" },
        { option = "statAgi",       label = "Agility" },
        { option = "statSta",       label = "Stamina" },
        { option = "statInt",       label = "Intellect" },
        { option = "statSpi",       label = "Spirit" },
        { option = "statAP",        label = "Attack power" },
        { option = "statSP",        label = "Spell power" },
        { option = "statCrit",      label = "Melee crit %" },
        { option = "statSpellCrit", label = "Spell crit %" },
        { option = "statHit",       label = "Melee hit %" },
        { option = "statSpellHit",  label = "Spell hit %" },
        { option = "statExpertise", label = "Expertise" },
    }
    -- Three to a row: twelve stacked checks would make the section as long as the
    -- flat page it replaced.
    for i = 1, #STAT_LABELS, 3 do
        local items = {}
        for j = i, math.min(i + 2, #STAT_LABELS) do
            local option = STAT_LABELS[j].option
            items[#items + 1] = {
                kind = "check", label = STAT_LABELS[j].label, width = 175,
                get = function() return cfg[option] end,
                set = function(v) cfg[option] = v end,
                onChange = UpdateStats,
            }
        end
        page:Row(items, { gap = 2 })
    end

    page:Check({
        label = "Hide stats sitting at zero",
        tooltip = "A stat with no value drops out of the list instead of taking up a line.",
        get = function() return cfg.statHideZero end,
        set = function(v) cfg.statHideZero = v end,
        onChange = UpdateStats,
    })

    page:Check({
        label = "Lock in place",
        tooltip = "Locked, the readout takes no mouse input at all, so clicks pass straight through "
            .. "it. Unlock it to move it with Ctrl + left-drag.",
        get = function() return cfg.statLocked end,
        set = function(v) cfg.statLocked = v end,
        onChange = UpdateStats,
    })

    page:Dropdown({
        label = "Layout", width = 150,
        options = { { "vertical", "Vertical list" }, { "horizontal", "One row" } },
        get = function() return cfg.statLayout end,
        set = function(v) cfg.statLayout = v end,
        onChange = UpdateStats,
    })

    page:Slider({
        label = "Font size", width = 200,
        min = 8, max = 24, step = 1,
        get = function() return cfg.statFontSize or 12 end,
        set = function(v) cfg.statFontSize = v end,
        onChange = UpdateStats,
    })

    page:Section({
        title = "Loot rolls",
        tooltip = "Lists recent group loot rolls under the objectives frame.",
        get = function() return cfg.lootRolls end,
        set = function(v) cfg.lootRolls = v end,
        onChange = RelayoutTracker,
    })
    page:Text("Adds a Loot Rolls section under the objectives frame listing the items you most "
        .. "recently rolled Need on, styled to match the tracker. Each item takes one line, showing the "
        .. "top roll so far and how many of the group have answered out of how many are in it. Hover "
        .. "an item for the full breakdown of who chose what and who has yet to roll; shift-click to "
        .. "link it in chat, ctrl-click to preview it.")

    page:Check({
        label = "Only list rolls you pressed Need on",
        tooltip = "A roll you passed or greeded resolves without you, so it stays off the list. "
            .. "What's left is just the items you actually asked for.\n\nAn item shows up once you've "
            .. "answered Need on it, so nothing appears while you're still deciding.",
        get = function() return cfg.lootRollsNeedOnly end,
        set = function(v) cfg.lootRollsNeedOnly = v end,
        onChange = RefreshLootRolls,
    })

    page:Check({
        label = "Attach to the objectives frame",
        tooltip = "On: the list sits underneath your tracked quests and follows them as they change.\n\n"
            .. "Off: the list becomes a free-floating box you can move with Ctrl + left-drag.",
        get = function() return cfg.lootRollsAttach end,
        set = function(v) cfg.lootRollsAttach = v end,
        onChange = RelayoutTracker,
    })

    page:Check({
        label = "Limit the quests the tracker lists",
        tooltip = "Long quest lists push the loot rolls section down the screen. This caps how many "
            .. "quests the objectives frame draws; the rest stay tracked, they're just not listed.\n\n"
            .. "Only applies while the loot rolls list is on and attached.",
        get = function() return cfg.lootRollsLimitQuests end,
        set = function(v) cfg.lootRollsLimitQuests = v end,
        onChange = RelayoutTracker,
    })

    page:Input({
        label = "Quests to list", width = 80,
        name = "HKSuiteLootRollsQuestLimitBox",
        tooltip = "How many quests the objectives frame shows while the loot rolls list is attached.",
        numeric = true, min = 1, max = 25, step = 1,
        get = function() return cfg.lootRollsQuestLimit end,
        set = function(v) cfg.lootRollsQuestLimit = v end,
        onChange = RelayoutTracker,
    })

    page:Input({
        label = "Items to list", width = 80,
        name = "HKSuiteLootRollsMaxBox",
        tooltip = "How many of the most recent items the section shows -- one line each.",
        numeric = true, min = 1, max = 10, step = 1,
        get = function() return cfg.lootRollsMax end,
        set = function(v) cfg.lootRollsMax = v end,
        onChange = RefreshLootRolls,
    })

    page:Input({
        label = "Hide the list this long after the last roll (seconds, 0 = never)", width = 80,
        name = "HKSuiteLootRollsHideBox",
        tooltip = "The section disappears once the newest roll has been finished for this long.",
        numeric = true, min = 0, max = 3600, step = 1,
        get = function() return cfg.lootRollsHideAfter end,
        set = function(v) cfg.lootRollsHideAfter = v end,
        onChange = RefreshLootRolls,
    })

    page:Section({
        title = "Path reminder",
        tooltip = "Warns on screen while your character has no Path applied.",
        get = function() return cfg.pathReminder end,
        set = function(v) cfg.pathReminder = v end,
        onChange = UpdatePathReminder,
    })
    page:Text("Shows a warning above your character whenever no Path is applied -- Path of Strength, "
        .. "Agility, Intelligence, Healing or Duality. It reads the same value the character sheet's "
        .. "Path line does, and disappears the moment one is set.")

    -- Reading the live value back is the quickest way to see the detection is
    -- working, so the page reports what it currently finds.
    local function PathStatus()
        local hasPath, name, supported = ActivePath()
        if not supported then
            return "|cffaaaaaaThis client doesn't report Paths, so the warning stays off.|r"
        end
        if not hasPath then return "Right now: |cffff4444no Path applied|r" end
        return "Right now: |cff1eff00" .. (name or "a Path is applied") .. "|r"
    end
    local status = page:Hint(PathStatus())
    page:OnRefresh(function() status:SetText(PathStatus()) end)

    page:Input({
        label = "Warning text", width = 260,
        name = "HKSuitePathReminderTextBox",
        fallback = ns.defaults.uifeatures.pathReminderText,
        get = function() return cfg.pathReminderText end,
        set = function(v) cfg.pathReminderText = v end,
        onChange = UpdatePathReminder,
    })

    page:Input({
        label = "Height above the middle of the screen (pixels)", width = 80,
        name = "HKSuitePathReminderYBox",
        tooltip = "Raise this if the warning overlaps your character.",
        numeric = true, min = -400, max = 400, step = 5,
        get = function() return cfg.pathReminderY end,
        set = function(v) cfg.pathReminderY = v end,
        onChange = UpdatePathReminder,
    })

    page:Input({
        label = "Font size", width = 80,
        name = "HKSuitePathReminderSizeBox",
        numeric = true, min = 8, max = 48, step = 1,
        get = function() return cfg.pathReminderSize end,
        set = function(v) cfg.pathReminderSize = v end,
        onChange = UpdatePathReminder,
    })
end

function M:OnInit()
    cfg = ns.GetConfig("uifeatures")

    BuildCross()
    BuildTrinketBox()
    BuildStatBox()
    BuildPathReminder()
    CompileLootPatterns()
    BuildLootRollsFrame()

    -- Loot rolls: START_LOOT_ROLL gives us the item, the chat traffic gives us
    -- the answers, CANCEL_LOOT_ROLL tells us the roll is over.
    local loot = CreateFrame("Frame")
    loot:RegisterEvent("START_LOOT_ROLL")
    loot:RegisterEvent("CANCEL_LOOT_ROLL")
    loot:RegisterEvent("CHAT_MSG_LOOT")
    loot:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not (enabled() and cfg.lootRolls) then return end
        if event == "START_LOOT_ROLL" then
            StartRoll(arg1, arg2)
        elseif event == "CANCEL_LOOT_ROLL" then
            local rec = rollByID[arg1]
            if rec then Finish(rec); MarkLootRolls() end
        else
            HandleLootMessage(arg1)
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit, spellName)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and spellName and spellName ~= "" then
                lastCastSpell = spellName
            end
            return
        elseif event == "SPELLS_CHANGED" then
            -- Your abilities changed, so a probe that found nothing might now
            -- succeed. Drop the back-off instead of waiting it out.
            InvalidateMeleeSpell()
            return
        end
        UpdateTrinkets()
    end)

    UpdateTrinkets()
    UpdateStats()
    UpdatePathReminder()
    RefreshLootRolls()
end
