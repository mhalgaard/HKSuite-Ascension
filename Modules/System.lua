local ADDON, ns = ...

-- =============================================================================
-- System module: graphics/loot/camera CVars. Modelled on Leatrix Plus.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "system",
    title = "System",
    desc  = "Disable screen glow/effects, zero weather density, fast auto loot.",
})

ns.defaults.system = {
    disableGlow          = false,
    disableScreenEffects = false,
    weatherZero          = false,
    fastLoot             = false,
    autoConfirmBoP       = false,   -- auto-confirm the bind-on-pickup loot prompt
    cameraFactor         = false,   -- number once the user moves the slider; else unmanaged
}

local cfg  -- filled in OnInit

-- Apply a single option's CVar. Restores the Blizzard default when toggled off.
local function ApplyOption(key)
    if key == "disableGlow" then
        SetCVar("ffxGlow", cfg.disableGlow and "0" or "1")
    elseif key == "disableScreenEffects" then
        SetCVar("ffxDeath", cfg.disableScreenEffects and "0" or "1")
        pcall(SetCVar, "ffxNetherWorld", cfg.disableScreenEffects and "0" or "1")
    elseif key == "weatherZero" then
        SetCVar("weatherDensity", cfg.weatherZero and "0" or "3")
    elseif key == "fastLoot" then
        if cfg.fastLoot then SetCVar("autoLootDefault", "1") end
    end
end

-- On load, only enforce the options that are ON, so we never override the
-- player's Blizzard settings for things they haven't opted into.
local function ApplyEnabled()
    if not ns.IsModuleEnabled("system") then return end
    if cfg.disableGlow then SetCVar("ffxGlow", "0") end
    if cfg.disableScreenEffects then
        SetCVar("ffxDeath", "0")
        pcall(SetCVar, "ffxNetherWorld", "0")
    end
    if cfg.weatherZero then SetCVar("weatherDensity", "0") end
    if cfg.fastLoot then SetCVar("autoLootDefault", "1") end
    if type(cfg.cameraFactor) == "number" then
        SetCVar("cameraDistanceMaxFactor", cfg.cameraFactor)
    end
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "System"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("System")

    local anchor = title
    local function AddOption(label, tip, key)
        local cb = ns.CreateCheck(panel, label, tip, cfg[key])
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, (anchor == title) and -12 or -8)
        cb:SetScript("OnClick", function(self)
            cfg[key] = self:GetChecked() and true or false
            ApplyOption(key)
        end)
        anchor = cb
    end

    AddOption("Disable screen glow",
        "Turns off the full-screen glow effect (ffxGlow).", "disableGlow")
    AddOption("Disable screen effects",
        "Turns off the death and nether screen effects (ffxDeath, ffxNetherWorld).", "disableScreenEffects")
    AddOption("Set weather density to 0",
        "Removes rain, snow and other weather (weatherDensity).", "weatherZero")
    AddOption("Enable fast auto loot",
        "Instantly loots everything when a corpse or object is opened.", "fastLoot")
    AddOption("Auto-confirm Bind-on-Pickup loot",
        "Automatically confirms the \"this item will bind to you\" loot prompt, regardless of quality.", "autoConfirmBoP")

    -- Camera distance slider (only starts managing the CVar once moved).
    local camSlider = CreateFrame("Slider", "HKSuiteCameraSlider", panel, "OptionsSliderTemplate")
    camSlider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -30)
    camSlider:SetMinMaxValues(1.0, 2.6)
    camSlider:SetValueStep(0.1)
    camSlider:SetWidth(220)
    _G[camSlider:GetName() .. "Low"]:SetText("Min")
    _G[camSlider:GetName() .. "High"]:SetText("Max")
    local initial = (type(cfg.cameraFactor) == "number" and cfg.cameraFactor)
        or tonumber(GetCVar("cameraDistanceMaxFactor")) or 1.0
    camSlider:SetValue(initial)   -- set before wiring OnValueChanged so it doesn't self-fire
    _G[camSlider:GetName() .. "Text"]:SetText("Camera distance: " .. string.format("%.1f", initial))
    camSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10 + 0.5) / 10
        cfg.cameraFactor = value
        SetCVar("cameraDistanceMaxFactor", value)
        _G[self:GetName() .. "Text"]:SetText("Camera distance: " .. string.format("%.1f", value))
    end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.config.system
    BuildOptionsPanel()

    -- Instant loot + bind-on-pickup confirmation.
    local lootFrame = CreateFrame("Frame")
    lootFrame:RegisterEvent("LOOT_OPENED")
    lootFrame:RegisterEvent("LOOT_BIND_CONFIRM")
    lootFrame:SetScript("OnEvent", function(_, event, arg1)
        if not ns.IsModuleEnabled("system") then return end
        if event == "LOOT_OPENED" then
            if arg1 then return end          -- arg1 = autoLooted; client already handled it
            if not cfg.fastLoot then return end
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
        elseif event == "LOOT_BIND_CONFIRM" then
            if cfg.autoConfirmBoP then
                ConfirmLootSlot(arg1)         -- arg1 = loot slot index
                StaticPopup_Hide("LOOT_BIND")
            end
        end
    end)

    -- Enforce enabled CVars on login and after each zone change.
    local cvarFrame = CreateFrame("Frame")
    cvarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cvarFrame:SetScript("OnEvent", ApplyEnabled)
end
