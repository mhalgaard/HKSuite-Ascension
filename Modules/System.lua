local ADDON, ns = ...

-- =============================================================================
-- System module: graphics/loot/camera CVars plus a handful of quality-of-life
-- tweaks (error suppression, auto-dismount, item deletion). Modelled on
-- Leatrix Plus.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "system",
    title = "System",
    desc  = "Screen/loot/camera tweaks, error hiding, auto-dismount, item deletion.",
})

ns.defaults.system = {
    disableGlow          = false,
    disableScreenEffects = false,
    weatherZero          = false,
    fastLoot             = false,
    autoConfirmBoP       = false,   -- auto-confirm the bind-on-pickup loot prompt
    cameraFactor         = false,   -- number once the user moves the slider; else unmanaged

    -- Errors
    hideErrors           = false,   -- hide the red error text in the middle of the screen
    muteErrorSpeech      = false,   -- silence the spoken error sounds (cooldown/GCD/etc.)

    -- Auto-dismount
    dismountOnAction     = false,   -- dismount when using an action (spell/item)
    dismountAtFlightMaster = false, -- dismount when opening a flight master's map

    -- Item deletion (folded in from the old Item Deletion module)
    deleteAutoFill       = true,    -- pre-fill "DELETE" in the confirmation box
    deleteInstant        = false,   -- skip the confirmation dialog entirely
    deleteMigrated       = false,   -- one-time flag: settings pulled from old "delete" table
}

local cfg  -- filled in OnInit

-- Apply a single option's effect. Restores the Blizzard default when toggled off.
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
    elseif key == "muteErrorSpeech" then
        SetCVar("Sound_EnableErrorSpeech", cfg.muteErrorSpeech and "0" or "1")
    end
    -- hideErrors needs no apply step: the AddMessage filter reads cfg live.
end

-- Suppress the red on-screen error text by filtering UIErrorsFrame's own
-- AddMessage, rather than unregistering the event. This is immune to other
-- addons (e.g. ElvUI) re-registering UI_ERROR_MESSAGE, and it preserves the
-- yellow/green info messages (quest updates, reputation, etc.) since we only
-- drop messages tinted with the red error color.
local function InstallErrorFilter()
    if ns._errorFilterInstalled then return end
    ns._errorFilterInstalled = true
    local orig = UIErrorsFrame.AddMessage
    UIErrorsFrame.AddMessage = function(self, msg, r, g, b, ...)
        if cfg and cfg.hideErrors and ns.IsModuleEnabled("system") then
            local rr, gg, bb = r or 1, g or 1, b or 1
            if rr > 0.9 and gg < 0.5 and bb < 0.5 then
                return   -- red error text: drop it
            end
        end
        return orig(self, msg, r, g, b, ...)
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
    if cfg.muteErrorSpeech then SetCVar("Sound_EnableErrorSpeech", "0") end
    if type(cfg.cameraFactor) == "number" then
        SetCVar("cameraDistanceMaxFactor", cfg.cameraFactor)
    end
end

-- ------------------------------------------------------------- auto-dismount
local function DismountIfMounted()
    if not ns.IsModuleEnabled("system") or not cfg.dismountOnAction then return end
    -- Never dismount in mid-air; that's a long way down.
    if IsMounted() and not IsFlying() then Dismount() end
end

-- ------------------------------------------------------------- item deletion
local CONFIRM = DELETE_ITEM_CONFIRM_STRING or "DELETE"

local function FindPopup(which)
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local frame = _G["StaticPopup" .. i]
        if frame and frame:IsShown() and frame.which == which then
            return frame, i
        end
    end
end

local function OnDeletePopup(which)
    if not ns.IsModuleEnabled("system") then return end

    local frame, i = FindPopup(which)
    if not frame then return end

    if cfg.deleteInstant then
        -- The item is on the cursor while the prompt is up; delete and dismiss.
        DeleteCursorItem()
        frame:Hide()
    elseif cfg.deleteAutoFill and which == "DELETE_GOOD_ITEM" then
        local editBox = frame.editBox or _G["StaticPopup" .. i .. "EditBox"]
        if editBox then
            editBox:SetText(CONFIRM)   -- fires OnTextChanged, enabling the confirm button
        end
    end
end

-- ------------------------------------------------------------------- options
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "System"
    panel.parent = "HKSuite"

    local scroll = CreateFrame("ScrollFrame", "HKSuiteSystemScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 760)
    scroll:SetScrollChild(content)

    local BASE_X = 12
    local y = -8

    local function Title(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", BASE_X, y); fs:SetText(text); y = y - 28
    end
    local function Header(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", BASE_X, y); fs:SetText("|cffffd100" .. text .. "|r"); y = y - 22
    end
    local function AddOption(label, tip, key)
        local cb = ns.CreateCheck(content, label, tip, cfg[key])
        cb:SetPoint("TOPLEFT", BASE_X, y)
        cb:SetScript("OnClick", function(self)
            cfg[key] = self:GetChecked() and true or false
            ApplyOption(key)
        end)
        y = y - 24
        return cb
    end

    Title("System")

    Header("Display")
    AddOption("Disable screen glow",
        "Turns off the full-screen glow effect.", "disableGlow")
    AddOption("Disable screen effects",
        "Turns off the death and nether-world screen effects.", "disableScreenEffects")
    AddOption("Set weather density to 0",
        "Removes rain, snow and other weather.", "weatherZero")

    -- Camera distance slider (only starts managing the CVar once moved).
    local camSlider = CreateFrame("Slider", "HKSuiteCameraSlider", content, "OptionsSliderTemplate")
    camSlider:SetPoint("TOPLEFT", BASE_X + 4, y - 18)
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
    y = y - 58

    Header("Loot")
    AddOption("Enable fast auto loot",
        "Instantly loots everything when a corpse or object is opened.", "fastLoot")
    AddOption("Auto-confirm Bind-on-Pickup loot",
        "Automatically confirms the \"this item will bind to you\" loot prompt, regardless of quality.", "autoConfirmBoP")

    Header("Errors")
    AddOption("Hide on-screen error messages",
        "Hides the red error text in the middle of the screen (e.g. \"Not enough rage\", \"Out of range\").", "hideErrors")
    AddOption("Disable error sounds (cooldown / GCD)",
        "Silences the spoken error sounds played when you use an ability that isn't ready yet or during the global cooldown.", "muteErrorSpeech")

    Header("Auto-dismount")
    AddOption("Dismount when using an action",
        "Automatically dismount when you cast a spell or use an item while mounted (never while flying).", "dismountOnAction")
    AddOption("Dismount at flight masters",
        "Automatically dismount when you open a flight master's map.", "dismountAtFlightMaster")

    Header("Item Deletion")
    AddOption("Auto-fill \"DELETE\" in deletion prompts",
        "When deleting a quality item that asks you to type DELETE, the word is filled in automatically so you only need to click confirm.", "deleteAutoFill")
    AddOption("Instant delete (skip the confirmation)",
        "|cffff2020Warning:|r deletes the item immediately with no confirmation dialog at all. Use with care.", "deleteInstant")

    content:SetHeight(-y + 20)
    InterfaceOptions_AddCategory(panel)
end

-- One-time migration of settings from the old standalone Item Deletion module.
local function MigrateDelete()
    if cfg.deleteMigrated then return end
    local old = ns.accountDB and ns.accountDB.delete
    if old then
        if old.autoFill ~= nil then cfg.deleteAutoFill = old.autoFill end
        if old.instantDelete ~= nil then cfg.deleteInstant = old.instantDelete end
    end
    cfg.deleteMigrated = true
end

function M:OnInit()
    cfg = ns.GetConfig("system")
    MigrateDelete()
    BuildOptionsPanel()
    InstallErrorFilter()

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
                if ElvUI and ElvUI[1] and ElvUI[1].StaticPopup_Hide then
                    pcall(ElvUI[1].StaticPopup_Hide, ElvUI[1], "LOOT_BIND")
                end
            end
        end
    end)

    -- Enforce enabled CVars on login and after each zone change.
    local cvarFrame = CreateFrame("Frame")
    cvarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cvarFrame:SetScript("OnEvent", ApplyEnabled)

    -- Auto-dismount at flight masters.
    local taxiFrame = CreateFrame("Frame")
    taxiFrame:RegisterEvent("TAXIMAP_OPENED")
    taxiFrame:SetScript("OnEvent", function()
        if not ns.IsModuleEnabled("system") or not cfg.dismountAtFlightMaster then return end
        if IsMounted() and not IsFlying() then Dismount() end
    end)

    -- Auto-dismount when using an action (spell or item).
    for _, fn in ipairs({ "UseAction", "CastSpell", "CastSpellByName",
                          "UseInventoryItem", "UseContainerItem" }) do
        if _G[fn] then hooksecurefunc(fn, DismountIfMounted) end
    end

    -- Item deletion: fill/skip the delete confirmation.
    hooksecurefunc("StaticPopup_Show", function(which)
        if which == "DELETE_GOOD_ITEM" or which == "DELETE_ITEM" then
            OnDeletePopup(which)
        end
    end)
end
