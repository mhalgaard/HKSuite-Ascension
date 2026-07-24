local ADDON, ns = ...

-- =============================================================================
-- UI Features module: small on-screen combat helpers.
--   * In-range tracker  — a crosshair over the character, white when the target
--     is in melee range, red when it's out of range.
--   * Trinket tracker   — a movable box showing your equipped trinkets and their
--     cooldowns (move with Ctrl + left-drag).
-- =============================================================================

local M = ns.RegisterModule({
    key   = "uifeatures",
    title = "UI Features",
    desc  = "In-range crosshair and a movable trinket cooldown tracker.",
})

ns.defaults.uifeatures = {
    rangeTracker   = false,
    rangeSpell     = "",       -- optional: exact ability name to range-check with
    trinketTracker = false,
    trinketPos     = { "CENTER", "CENTER", 0, -160 },  -- point, relPoint, x, y
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
local function ResolveMeleeSpell()
    local custom = cfg.rangeSpell
    if custom and custom ~= "" and IsSpellInRange(custom, "target") ~= nil then
        return custom
    end
    if cachedSpell and IsSpellInRange(cachedSpell, "target") ~= nil then
        return cachedSpell
    end
    for _, name in ipairs(MELEE_SPELLS) do
        if IsSpellInRange(name, "target") ~= nil then
            cachedSpell = name
            return name
        end
    end
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
    local function ShowBars(show)
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
local PAD, GAP = 4, 4

local trinketBox, icons

local function FormatTime(r)
    if r >= 60 then return math.floor(r / 60) .. "m" end
    return tostring(math.ceil(r))
end

local function UpdateTrinkets()
    if not trinketBox then return end
    if not (enabled() and cfg.trinketTracker) then
        trinketBox:Hide()
        return
    end
    trinketBox:Show()
    for i, slot in ipairs(SLOTS) do
        local icon = icons[i]
        local tex = GetInventoryItemTexture("player", slot)
        if tex then
            icon.texture:SetTexture(tex)
            icon.texture:Show()
            local start, duration, enable = GetInventoryItemCooldown("player", slot)
            if enable == 1 and duration and duration > 0 and start > 0 then
                icon.cd:SetCooldown(start, duration)
            else
                icon.cd:SetCooldown(0, 0)
                icon.text:SetText("")
            end
        else
            icon.texture:Hide()      -- empty slot: keep the frame (so the box stays draggable)
            icon.cd:SetCooldown(0, 0)
            icon.text:SetText("")
        end
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
    trinketBox:SetFrameStrata("MEDIUM")
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

    -- Numeric cooldown countdown (the sweep alone has no number in 3.3.5).
    trinketBox:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.1 then return end
        self.elapsed = 0
        for i, slot in ipairs(SLOTS) do
            local icon = icons[i]
            if icon.texture:IsShown() then
                local start, duration, enable = GetInventoryItemCooldown("player", slot)
                if enable == 1 and duration and duration > 0 and start > 0 then
                    local r = start + duration - GetTime()
                    icon.text:SetText(r > 0 and FormatTime(r) or "")
                else
                    icon.text:SetText("")
                end
            end
        end
    end)

    trinketBox:Hide()
end

-- ------------------------------------------------------------------- options
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "UI Features"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("UI Features")

    local range = ns.CreateCheck(panel, "Enable in-range tracker",
        "Shows a crosshair over your character: white when your target is in melee range, red when out of range.",
        cfg.rangeTracker)
    range:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    range:SetScript("OnClick", function(self)
        cfg.rangeTracker = self:GetChecked() and true or false
    end)

    local spellLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", range, "BOTTOMLEFT", 24, -6)
    spellLabel:SetText("Melee ability for range check (optional — auto-detected if blank):")

    local spellBox = CreateFrame("EditBox", "HKSuiteRangeSpellBox", panel, "InputBoxTemplate")
    spellBox:SetSize(200, 20)
    spellBox:SetAutoFocus(false)
    spellBox:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 4, -8)
    spellBox:SetText(cfg.rangeSpell or "")

    local savedLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local function RefreshSaved()
        local v = cfg.rangeSpell
        if v and v ~= "" then
            savedLabel:SetText("Saved: |cff00ff00" .. v .. "|r")
        else
            savedLabel:SetText("Saved: |cffaaaaaa(auto-detect)|r")
        end
    end

    local function ApplySpell(name)
        cfg.rangeSpell = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        cachedSpell = nil            -- force re-resolve with the new preference
        spellBox:SetText(cfg.rangeSpell)
        RefreshSaved()
    end
    local function SaveSpell() ApplySpell(spellBox:GetText()) end

    spellBox:SetScript("OnEnterPressed", function(self) SaveSpell(); self:ClearFocus() end)
    spellBox:SetScript("OnEditFocusLost", SaveSpell)
    spellBox:SetScript("OnEscapePressed", function(self)
        self:SetText(cfg.rangeSpell or ""); self:ClearFocus()
    end)

    local okBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    okBtn:SetSize(48, 22)
    okBtn:SetPoint("LEFT", spellBox, "RIGHT", 8, 0)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", function() SaveSpell(); spellBox:ClearFocus() end)

    savedLabel:SetPoint("TOPLEFT", spellBox, "BOTTOMLEFT", 0, -6)
    RefreshSaved()

    -- Reliable capture: set to the last ability you cast. (The Blizzard spellbook
    -- can't be open at the same time as this options panel, which is why
    -- shift-clicking a spell here usually can't work.)
    local lastBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lastBtn:SetSize(190, 22)
    lastBtn:SetPoint("TOPLEFT", savedLabel, "BOTTOMLEFT", 0, -6)
    lastBtn:SetText("Set from last-used ability")
    lastBtn:SetScript("OnClick", function()
        if lastCastSpell and lastCastSpell ~= "" then
            ApplySpell(lastCastSpell)
            ns.Print("Range ability set to: " .. lastCastSpell)
        else
            ns.Print("Cast your melee ability once, then click 'Set from last-used ability'.")
        end
    end)

    -- Also accept a Shift-clicked spell link if the box has focus (works with a
    -- standalone spell list; the default spellbook closes this panel).
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and spellBox:HasFocus() then
            ApplySpell(tostring(link):match("%[(.-)%]") or tostring(link))
        end
    end)

    local tipShift = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tipShift:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -6)
    tipShift:SetText("Type the exact ability name and click OK, or use the button above.")

    local trinket = ns.CreateCheck(panel, "Enable trinket tracker",
        "Shows your equipped trinkets and their cooldowns in a box. Hold Ctrl and left-drag to move it.",
        cfg.trinketTracker)
    trinket:SetPoint("TOPLEFT", tipShift, "BOTTOMLEFT", -28, -14)
    trinket:SetScript("OnClick", function(self)
        cfg.trinketTracker = self:GetChecked() and true or false
        UpdateTrinkets()
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", trinket, "BOTTOMLEFT", 20, -6)
    hint:SetText("Tip: hold Ctrl + left-click and drag the trinket box to reposition it.")

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("uifeatures")

    BuildCross()
    BuildTrinketBox()
    BuildOptionsPanel()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:SetScript("OnEvent", function(_, event, unit, spellName)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and spellName and spellName ~= "" then
                lastCastSpell = spellName
            end
            return
        end
        UpdateTrinkets()
    end)

    UpdateTrinkets()
end
