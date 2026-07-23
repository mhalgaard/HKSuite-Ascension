local ADDON, ns = ...

-- Shared namespace for all modules in the suite.
ns.name = "HKSuite"
ns.version = "1.2.0"
ns.modules = {}
ns.defaults = {}   -- modules populate this at file-load time

-- Chat helper. Echoes to the General tab and, if it exists, a "Guild" tab too.
local PREFIX = "|cff1eff00HKSuite|r: "
local function GuildChatFrame()
    for i = 1, NUM_CHAT_WINDOWS do
        local name = GetChatWindowInfo(i)
        if name and name:lower() == "guild" then
            return _G["ChatFrame" .. i]
        end
    end
end
function ns.Print(msg)
    local text = PREFIX .. tostring(msg)
    DEFAULT_CHAT_FRAME:AddMessage(text)
    local gf = GuildChatFrame()
    if gf and gf ~= DEFAULT_CHAT_FRAME then
        gf:AddMessage(text)
    end
end

-- Register a module table. Recognised fields:
--   key            (string) unique id, also the SavedVariables sub-table name
--   title          (string) display name shown on the Overview page
--   desc           (string) one-line description (tooltip on the Overview)
--   defaultEnabled (bool)   default enabled state (true unless set to false)
--   OnInit         (func)   called once after SavedVariables are ready
-- A module with a key automatically appears on the Overview with an
-- enable/disable toggle and an account/per-character scope toggle.
function ns.RegisterModule(module)
    table.insert(ns.modules, module)
    return module
end

-- ============================ Settings scope =================================
-- Each module's settings live in either the account DB (shared by all
-- characters) or the per-character DB. The scope choice is itself per-character,
-- so each character independently opts a module into its own settings. New
-- characters default every module to "account".

local function CopyTable(src)
    local t = {}
    for k, v in pairs(src) do
        if type(v) == "table" then t[k] = CopyTable(v) else t[k] = v end
    end
    return t
end

function ns.GetScope(key)
    return (ns.charDB.scope and ns.charDB.scope[key]) or "account"
end

-- The active settings table for a module, per its current scope.
function ns.GetConfig(key)
    if ns.GetScope(key) == "character" then
        ns.charDB[key] = ns.charDB[key] or {}
        return ns.charDB[key]
    end
    return ns.accountDB[key]
end

-- Whether a module is currently enabled (default true), scope-aware.
function ns.IsModuleEnabled(key)
    if ns.GetScope(key) == "character" then
        local v = ns.charDB.modules[key]
        if v == nil then v = ns.accountDB.modules[key] end
        return v ~= false
    end
    return ns.accountDB.modules[key] ~= false
end

function ns.SetModuleEnabled(key, val)
    if ns.GetScope(key) == "character" then
        ns.charDB.modules[key] = val
    else
        ns.accountDB.modules[key] = val
    end
end

-- Switch a module's scope. Switching to per-character seeds the character
-- settings from the current account settings. Takes effect after a reload
-- (modules read their config table once at load).
function ns.SetScope(key, scope)
    if scope == "character" then
        if not ns.charDB[key] then
            ns.charDB[key] = CopyTable(ns.accountDB[key] or {})
        end
        if ns.charDB.modules[key] == nil then
            ns.charDB.modules[key] = ns.accountDB.modules[key]
        end
        ns.charDB.scope[key] = "character"
    else
        ns.charDB.scope[key] = "account"
    end
end

-- ============================== UI helper ====================================
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

-- Reload prompt shown after scope changes.
StaticPopupDialogs["HKSUITE_RELOAD"] = {
    text = "HKSuite: reload the UI to apply the settings scope change?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function ns.PromptReload()
    StaticPopup_Show("HKSUITE_RELOAD")
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
        HKSuiteCharDB = HKSuiteCharDB or {}
        ns.accountDB = HKSuiteDB
        ns.charDB = HKSuiteCharDB
        ns.config = HKSuiteDB    -- account-level defaults live here

        CopyDefaults(ns.defaults, ns.accountDB)

        ns.accountDB.modules = ns.accountDB.modules or {}
        ns.charDB.modules = ns.charDB.modules or {}
        ns.charDB.scope = ns.charDB.scope or {}

        -- Default enable flags (account).
        for _, module in ipairs(ns.modules) do
            if module.key and ns.accountDB.modules[module.key] == nil then
                ns.accountDB.modules[module.key] = (module.defaultEnabled ~= false)
            end
        end

        -- Make sure any existing per-character tables get newly-added defaults.
        for _, module in ipairs(ns.modules) do
            local key = module.key
            if key and ns.charDB[key] and ns.defaults[key] then
                CopyDefaults(ns.defaults[key], ns.charDB[key])
            end
        end

        -- Sort modules alphabetically by title so the Overview list and the
        -- Interface Options sub-pages appear in alphabetical order.
        table.sort(ns.modules, function(a, b)
            return (a.title or "") < (b.title or "")
        end)

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
