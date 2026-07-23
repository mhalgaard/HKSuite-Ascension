local ADDON, ns = ...

-- =============================================================================
-- Loot Auto Roller module.
-- Standard group-loot API (START_LOOT_ROLL / RollOnLoot / CONFIRM_LOOT_ROLL).
-- Ascension adds quality 6 ("Vanity", gold), which is included below.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "lootroll",
    title = "Loot Auto Roller",
    desc  = "Automatically pass/greed/disenchant/need on loot rolls, by item quality.",
    defaultEnabled = false,
})

ns.defaults.lootroll = {
    rollOnBoP = false,   -- when off, BoP items are left for manual rolling
    quality = {
        [0] = "greed",   -- Poor
        [1] = "greed",   -- Common
        [2] = "greed",   -- Uncommon
        [3] = "none",    -- Rare
        [4] = "none",    -- Epic
        [5] = "none",    -- Legendary
        [6] = "greed",   -- Vanity (Ascension)
    },
}

local cfg
local autoRolled = {}    -- rollIDs we initiated, so we only auto-confirm our own

-- Decide and cast the roll for a given rollID.
local function DoRoll(rollID)
    if not ns.IsModuleEnabled("lootroll") then return end
    local _, _, _, quality, bop, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if quality == nil then return end

    local action = cfg.quality[quality]
    if not action or action == "none" then return end
    if bop and not cfg.rollOnBoP then return end   -- BoP protection

    local rollType
    if action == "pass" then
        rollType = 0
    elseif action == "need" then
        rollType = canNeed and 1 or (canGreed and 2 or 0)          -- fall back to greed, then pass
    elseif action == "greed" then
        rollType = canGreed and 2 or 0
    elseif action == "disenchant" then
        rollType = canDisenchant and 3 or (canGreed and 2 or 0)    -- fall back to greed, then pass
    else
        return
    end

    autoRolled[rollID] = true
    RollOnLoot(rollID, rollType)
end

-- ---------------------------------------------------------------- Options UI
local QUALITY_ORDER = { 0, 1, 2, 3, 4, 5, 6 }
local QUALITY_NAMES = {
    [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
    [4] = "Epic", [5] = "Legendary", [6] = "Vanity",
}
local ROLL_OPTIONS = {
    { value = "none",       text = "No auto-roll" },
    { value = "pass",       text = "Pass" },
    { value = "greed",      text = "Greed" },
    { value = "disenchant", text = "Disenchant" },
    { value = "need",       text = "Need" },
}
local ROLL_LABEL = {}
for _, o in ipairs(ROLL_OPTIONS) do ROLL_LABEL[o.value] = o.text end

local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Loot Auto Roller"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Loot Auto Roller")

    local bop = ns.CreateCheck(panel, "Also auto-roll on Bind-on-Pickup items",
        "When off (default), BoP items are left for you to roll manually.", cfg.rollOnBoP)
    bop:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    bop:SetScript("OnClick", function(self) cfg.rollOnBoP = self:GetChecked() and true or false end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", bop, "BOTTOMLEFT", 4, -12)
    hint:SetText("Action per item quality:")

    local anchor = hint
    for _, q in ipairs(QUALITY_ORDER) do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(320, 28)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, (anchor == hint) and -6 or -4)

        local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 4, 0)
        label:SetWidth(90)
        label:SetJustifyH("LEFT")
        label:SetText(QUALITY_NAMES[q])
        label:SetTextColor(QualityColor(q))

        local dd = CreateFrame("Frame", "HKSuiteRollDD" .. q, row, "UIDropDownMenuTemplate")
        dd:SetPoint("LEFT", label, "RIGHT", -6, 0)
        UIDropDownMenu_SetWidth(dd, 110)
        UIDropDownMenu_SetText(dd, ROLL_LABEL[cfg.quality[q]] or "No auto-roll")
        UIDropDownMenu_Initialize(dd, function(self, level)
            for _, opt in ipairs(ROLL_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.text
                info.value = opt.value
                info.checked = (cfg.quality[q] == opt.value)
                info.func = function(btn)
                    cfg.quality[q] = btn.value
                    UIDropDownMenu_SetText(dd, ROLL_LABEL[btn.value])
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        anchor = row
    end

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.config.lootroll
    BuildOptionsPanel()

    local f = CreateFrame("Frame")
    f:RegisterEvent("START_LOOT_ROLL")
    f:RegisterEvent("CONFIRM_LOOT_ROLL")
    f:SetScript("OnEvent", function(_, event, id, rollType)
        if event == "START_LOOT_ROLL" then
            DoRoll(id)
        elseif event == "CONFIRM_LOOT_ROLL" then
            if autoRolled[id] then          -- only confirm rolls we cast
                ConfirmLootRoll(id, rollType)
                autoRolled[id] = nil
            end
        end
    end)
end
