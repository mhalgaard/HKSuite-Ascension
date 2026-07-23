local ADDON, ns = ...

-- =============================================================================
-- Addon Button module.
-- A movable square "HK" button opens a flyout that consolidates other addons'
-- minimap buttons.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "addonbutton",
    title = "Addon Button",
    desc  = "Consolidates addon minimap buttons into one HK flyout menu.",
})

ns.defaults.addonbutton = {
    showButton = true,   -- show the movable HK button
    buttonPos  = false,  -- {point, relPoint, x, y} once the user moves it
}

local cfg
local button, menu
local collected, collectedSet = {}, {}

-- Blizzard minimap frames we never want to pull into the menu.
local IGNORE = {
    MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
    MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
    MiniMapMailFrame = true, MiniMapMailBorder = true, MiniMapBattlefieldFrame = true,
    MiniMapLFGFrame = true, GameTimeFrame = true, TimeManagerClockButton = true,
    MiniMapVoiceChatFrame = true, MinimapBackdrop = true, MiniMapInstanceDifficulty = true,
    MinimapZoneTextButton = true, MinimapNorthTag = true, HKSuiteAddonButton = true,
}

local function CollectButtons()
    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = child:GetName()
        if name and not IGNORE[name] and child.IsObjectType and child:IsObjectType("Button")
            and not collectedSet[child] then
            collectedSet[child] = true
            table.insert(collected, child)
        end
    end
end

local function LayoutMenu()
    CollectButtons()
    local cols, size, pad = 4, 33, 8
    local n = 0
    for _, b in ipairs(collected) do
        if b:GetParent() ~= menu then b:SetParent(menu) end
        b:ClearAllPoints()
        local col, row = n % cols, math.floor(n / cols)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + col * size, -(pad + row * size))
        b:SetFrameStrata("DIALOG")
        b:Show()
        n = n + 1
    end
    local rows = math.max(1, math.ceil(n / cols))
    menu:SetWidth(pad * 2 + math.min(n > 0 and n or 1, cols) * size)
    menu:SetHeight(pad * 2 + rows * size)
    menu.empty:SetShown(n == 0)
end

local function AnchorMenu()
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)   -- flyout from the button
end

local function ToggleMenu()
    if not ns.IsModuleEnabled("addonbutton") then return end
    if menu:IsShown() then
        menu:Hide()
    else
        LayoutMenu()
        AnchorMenu()
        menu:Show()
    end
end

local function BACKDROP()
    return {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }
end

local function RestoreButtonPos()
    button:ClearAllPoints()
    if type(cfg.buttonPos) == "table" then
        button:SetPoint(cfg.buttonPos[1], UIParent, cfg.buttonPos[2], cfg.buttonPos[3], cfg.buttonPos[4])
    else
        button:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)   -- default: minimap corner
    end
end

local function CreateWidgets()
    -- Flyout menu.
    menu = CreateFrame("Frame", "HKSuiteAddonMenu", UIParent)
    menu:SetBackdrop(BACKDROP())
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    menu:SetFrameStrata("DIALOG")   -- position set dynamically in AnchorMenu
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.empty:SetPoint("CENTER")
    menu.empty:SetText("No addon buttons found")
    menu.empty:Hide()

    -- Movable HK button.
    button = CreateFrame("Button", "HKSuiteAddonButton", UIParent)
    button:SetSize(24, 24)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",   -- solid 1px border
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    button:SetBackdropColor(0, 0, 0, 0.85)
    button:SetBackdropBorderColor(0, 0, 0, 1)         -- black border
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("HK")
    label:SetTextColor(0.12, 1, 0.12)

    button:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        cfg.buttonPos = { point, relPoint, x, y }
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() and IsControlKeyDown() and ns.ClearQuests then
                ns.ClearQuests(false)   -- instant clear using the whitelist/settings
            end
            return
        end
        if IsControlKeyDown() then return end   -- CTRL is reserved for dragging
        if IsShiftKeyDown() then
            InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)  -- twice: WotLK quirk
            return
        end
        ToggleMenu()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("HKSuite")
        GameTooltip:AddLine("Click: addon buttons menu", 1, 1, 1)
        GameTooltip:AddLine("Shift+click: HKSuite options", 1, 1, 1)
        GameTooltip:AddLine("Shift+CTRL+right-click: clear quests", 1, 1, 1)
        GameTooltip:AddLine("CTRL+drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    RestoreButtonPos()
end

local function ApplyButton()
    button:SetShown(cfg.showButton and ns.IsModuleEnabled("addonbutton"))
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Addon Button"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Addon Button")

    local sb = ns.CreateCheck(panel, "Show the movable HK button",
        "Displays a square HK button (CTRL+drag to move) that opens the addon-buttons menu.", cfg.showButton)
    sb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    sb:SetScript("OnClick", function(self)
        cfg.showButton = self:GetChecked() and true or false
        ApplyButton()
    end)

    local rescan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rescan:SetSize(160, 24)
    rescan:SetText("Rescan / reset position")
    rescan:SetPoint("TOPLEFT", sb, "BOTTOMLEFT", 0, -16)
    rescan:SetScript("OnClick", function()
        cfg.buttonPos = false
        RestoreButtonPos()
        LayoutMenu()
    end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("addonbutton")
    CreateWidgets()
    ApplyButton()
    BuildOptionsPanel()

    -- Grab minimap buttons on load. Two delayed passes catch addons that
    -- create their button late.
    local function grab()
        if ns.IsModuleEnabled("addonbutton") and cfg.showButton then LayoutMenu() end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(2, grab)
            C_Timer.After(5, grab)
        else
            grab()
        end
    end)
end
