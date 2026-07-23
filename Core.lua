local ADDON, ns = ...

-- Shared namespace for all modules in the suite.
ns.name = "HKSuite"
ns.version = "0.1.0"
ns.modules = {}
ns.defaults = {}   -- modules populate this at file-load time

-- Chat helper.
local PREFIX = "|cff1eff00HKSuite|r: "
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- Register a module table. Recognised fields:
--   key    (string) unique id, also the SavedVariables sub-table name
--   title  (string) display name shown on the Overview page
--   desc   (string) one-line description (tooltip on the Overview)
--   OnInit (function) called once after SavedVariables are ready
-- A module with a key automatically gets an enable/disable toggle on the
-- Overview page and an entry in ns.config.modules.
function ns.RegisterModule(module)
    table.insert(ns.modules, module)
    return module
end

-- Whether a module is currently enabled (default true).
function ns.IsModuleEnabled(key)
    return ns.config.modules[key] ~= false
end

-- Shared UI helper: a labelled checkbox with an optional tooltip.
local checkCount = 0
function ns.CreateCheck(parent, label, tooltip, checked)
    checkCount = checkCount + 1
    local cb = CreateFrame("CheckButton", "HKSuiteCheck" .. checkCount, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.label = _G[cb:GetName() .. "Text"]
    cb.label:SetText(label)
    cb:SetChecked(checked)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

-- Recursively fill `dst` with any values from `src` that are missing.
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        HKSuiteDB = HKSuiteDB or {}
        ns.config = HKSuiteDB
        CopyDefaults(ns.defaults, ns.config)

        -- Per-module enabled flags (default on).
        ns.config.modules = ns.config.modules or {}
        for _, module in ipairs(ns.modules) do
            if module.key and ns.config.modules[module.key] == nil then
                ns.config.modules[module.key] = (module.defaultEnabled ~= false)
            end
        end

        -- Build the Overview page first so module option panels can nest under it.
        if ns.BuildOverview then ns.BuildOverview() end

        for _, module in ipairs(ns.modules) do
            if module.OnInit then module:OnInit() end
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Slash command opens the Overview page.
SLASH_HKSUITE1 = "/hk"
SLASH_HKSUITE2 = "/hksuite"
SlashCmdList["HKSUITE"] = function()
    InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)
    InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)  -- twice: WotLK quirk
end

-- Convenience /rl to reload the UI, unless another addon already provides it.
if not (SLASH_RL1 or (hash_SlashCmdList and hash_SlashCmdList["/RL"]) or SlashCmdList["RL"]) then
    SLASH_HKRELOAD1 = "/rl"
    SlashCmdList["HKRELOAD"] = function() ReloadUI() end
end
