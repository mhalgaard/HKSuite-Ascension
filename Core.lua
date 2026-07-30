local ADDON, ns = ...

-- Shared namespace for all modules in the suite.
ns.name = "HKSuite"
-- Fallback only: the settings window reads the .toc via GetAddOnMetadata, which
-- the release workflow rewrites from the tag. Keep this in step with the .toc.
ns.version = "2.2.0"
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

-- One-shot delayed call, shared because several modules need to get out from
-- under whatever called them before acting. C_Timer when the client provides it;
-- otherwise an OnUpdate ticker off a small pool, since frames are never garbage
-- collected and these fire often enough (every BoP loot, every vendor visit) for
-- one-per-call to add up over a session.
local timerPool = {}

function ns.After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
        return
    end

    local f = table.remove(timerPool) or CreateFrame("Frame")
    f.elapsed, f.delay, f.fn = 0, delay, fn
    f:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed < self.delay then return end
        local callback = self.fn
        self.fn = nil
        self:SetScript("OnUpdate", nil)
        self:Hide()
        timerPool[#timerPool + 1] = self
        callback()
    end)
    f:Show()
end

-- Register a module table. Recognised fields:
--   key            (string) unique id, also the SavedVariables sub-table name
--   title          (string) display name shown in the settings window
--   desc           (string) one-line description (shown under the page title)
--   defaultEnabled (bool)   default enabled state (true unless set to false)
--   OnInit         (func)   called once after SavedVariables are ready
--   BuildSettings  (func)   self, page -> describes the module's settings page
--   OnToggle       (func)   self, enabled -> called when the rail switch flips
--   reloadOnToggle (bool)   the switch only takes effect after a UI reload, so
--                           the window raises its reload banner when it flips
-- A module with a key automatically gets a row in the settings window's rail,
-- with an enable/disable switch and an account/per-character scope control.
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
-- Checkboxes, dropdowns and the rest of the settings widgets live in ns.UI
-- (SettingsUI.lua). What remains here is the one helper the widgets themselves
-- build on.
--
-- An accept button that lives *inside* an input instead of beside it: a small
-- checkmark set into the box's edge, the way Blizzard's own inline inputs read.
-- Clicking it runs `onAccept` and drops focus, so a value commits without having
-- to click away from the box first.
--
-- Single-line boxes get the check in their right edge, and their text inset is
-- widened so typing never runs underneath it. Multi-line boxes live inside a
-- scroll frame, so they pass that frame as `host` and the check lands in its
-- top-right corner instead.
function ns.CreateInlineAccept(editBox, onAccept, host, point, xOff, yOff)
    local inline = (host == nil)
    host = host or editBox
    point = point or "RIGHT"

    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(16, 16)
    btn:SetPoint(point, host, point, xOff or (inline and -4 or -6), yOff or 0)
    btn:SetFrameLevel(host:GetFrameLevel() + 4)

    btn:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Check")
    btn:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    btn:GetHighlightTexture():SetBlendMode("ADD")
    btn:GetNormalTexture():SetAlpha(0.7)      -- quiet until pointed at

    btn:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Save", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        if onAccept then onAccept() end
        editBox:ClearFocus()
    end)

    -- Keep the text clear of the check on single-line boxes.
    if inline and editBox.GetTextInsets and editBox.SetTextInsets then
        local l, r, t, b = editBox:GetTextInsets()
        editBox:SetTextInsets(l or 0, math.max(r or 0, 22), t or 0, b or 0)
    end

    return btn
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

        -- A one-button page in Interface -> AddOns that opens the real window.
        if ns.BuildOptionsStub then
            local ok, err = pcall(ns.BuildOptionsStub)
            if not ok then ns.Print("|cffff2020Options stub error:|r " .. tostring(err)) end
        end

        -- Initialize each module independently: a failure in one must not stop
        -- the rest from loading (and we name the culprit so it can be fixed).
        for _, module in ipairs(ns.modules) do
            if module.OnInit then
                local ok, err = pcall(module.OnInit, module)
                if not ok then
                    ns.Print("|cffff2020Error initializing " ..
                        (module.title or module.key or "?") .. ":|r " .. tostring(err))
                end
            end
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Slash command opens HKSuite's own settings window. "/hk <module key>" jumps
-- straight to that module's page.
SLASH_HKSUITE1 = "/hk"
SLASH_HKSUITE2 = "/hksuite"
SlashCmdList["HKSUITE"] = function(msg)
    local key = (msg or ""):match("^%s*(%S*)"):lower()
    if key ~= "" then ns.OpenSettings(key) else ns.ToggleSettings() end
end

-- Convenience /rl to reload the UI, unless another addon already provides it.
if not (SLASH_RL1 or (hash_SlashCmdList and hash_SlashCmdList["/RL"]) or SlashCmdList["RL"]) then
    SLASH_HKRELOAD1 = "/rl"
    SlashCmdList["HKRELOAD"] = function() ReloadUI() end
end
