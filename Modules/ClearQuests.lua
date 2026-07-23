local ADDON, ns = ...

-- =============================================================================
-- Clear Quests module: abandon unwanted quests while keeping the ones you pick.
-- Ported from the ClearQuests addon.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "clearquests",
    title = "Clear Quests",
    desc  = "Abandon unwanted quests, keeping completed/daily/dungeon/whitelisted.",
})

ns.defaults.clearquests = {
    keepComplete               = true,
    keepTrivialComplete        = false,
    keepDaily                  = true,
    keepDungeon                = true,
    keepTrivialDungeon         = false,
    keepAscension              = true,
    keepPartialProgress        = false,
    keepTrivialPartialProgress = false,
    whitelist                  = {},   -- quest titles to always keep
}

local cfg

-- ------------------------------------------------------------------- logic
local function tableContains(tbl, val)
    for _, v in pairs(tbl) do if v == val then return true end end
    return false
end

local function isTrivial(playerLevel, questLevel)
    return playerLevel >= (questLevel or 0) + 10
end

local function hasPartialProgress(questIndex)
    local num = GetNumQuestLeaderBoards(questIndex)
    if num == 0 then return false end
    for i = 1, num do
        local desc, _, done = GetQuestLogLeaderBoard(i, questIndex)
        if done then return true end
        if desc then
            local cur = desc:match("(%d+)/%d+")
            if cur and tonumber(cur) and tonumber(cur) > 0 then return true end
        end
    end
    return false
end

local function shouldKeep(title, level, tag, isComplete, isDaily, playerLevel, index)
    if title:match("Prestige") or title:match("Mentorship") then return true end
    local trivial = isTrivial(playerLevel, level)

    if cfg.keepAscension and title:match("Path to Ascension") then return true end
    if cfg.keepComplete and isComplete == 1 and (not trivial or cfg.keepTrivialComplete) then return true end
    if cfg.keepDaily and isDaily == 1 then return true end
    if cfg.keepDungeon and tag == "Dungeon" and (not trivial or cfg.keepTrivialDungeon) then return true end
    if cfg.keepPartialProgress and hasPartialProgress(index)
        and (not trivial or cfg.keepTrivialPartialProgress) then return true end
    if tableContains(cfg.whitelist, title) then return true end

    return false
end

local function getQuestsToAbandon()
    local playerLevel = UnitLevel("player")
    local list = {}
    for i = 1, GetNumQuestLogEntries() do
        local title, level, tag, _, isHeader, _, isComplete, isDaily = GetQuestLogTitle(i)
        if title and not isHeader then
            if not shouldKeep(title, level, tag, isComplete, isDaily, playerLevel, i) then
                list[#list + 1] = { index = i, title = title, level = level or "?", tag = tag or "" }
            end
        end
    end
    return list
end

local function executeClear(list)
    if #list == 0 then return end
    -- Abandon highest index first so earlier indices stay valid.
    for i = #list, 1, -1 do
        SelectQuestLogEntry(list[i].index)
        SetAbandonQuest()
        AbandonQuest()
    end
    local names = {}
    for _, q in ipairs(list) do names[#names + 1] = q.title end
    ns.Print("Abandoned " .. #list .. " quest(s): " .. table.concat(names, ", "))
end

local pendingQuests = {}

StaticPopupDialogs["HKSUITE_CLEARQUESTS"] = {
    text = "Abandon %d quest(s)?\nSee chat for the list. This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() executeClear(pendingQuests); pendingQuests = {} end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

-- Public entry. confirm=true shows a confirmation; false clears immediately.
function ns.ClearQuests(confirm)
    if not ns.IsModuleEnabled("clearquests") then
        ns.Print("Clear Quests module is disabled.")
        return
    end
    local list = getQuestsToAbandon()
    if #list == 0 then ns.Print("No quests to abandon based on your settings.") return end
    if confirm then
        pendingQuests = list
        local names = {}
        for i, q in ipairs(list) do
            if i > 40 then names[#names + 1] = "…"; break end
            names[#names + 1] = q.title
        end
        ns.Print("Will abandon " .. #list .. " quest(s): " .. table.concat(names, ", "))
        StaticPopup_Show("HKSUITE_CLEARQUESTS", #list)
    else
        executeClear(list)
    end
end

-- ------------------------------------------------------------------- options
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Clear Quests"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Clear Quests")

    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(160, 24)
    clearBtn:SetText("Clear quests now")
    clearBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    clearBtn:SetScript("OnClick", function() ns.ClearQuests(true) end)

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    note:SetText("Prestige and Mentorship quests are always kept.")

    -- Fixed columns + running y so top-level checks align and sub-options indent
    -- consistently (no drifting staircase).
    local BASE_X = 16
    local yPos = -74
    local function AddCheck(label, tip, key, indent)
        local cb = ns.CreateCheck(panel, label, tip, cfg[key])
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X + (indent and 22 or 0), yPos)
        cb:SetScript("OnClick", function(self) cfg[key] = self:GetChecked() and true or false end)
        yPos = yPos - (indent and 22 or 26)
        return cb
    end

    AddCheck("Keep completed quests", "Keep non-trivial quests that are complete.", "keepComplete")
    AddCheck("…including trivial (10+ levels below)", "Also keep completed quests far below your level.", "keepTrivialComplete", true)
    AddCheck("Keep daily quests", "Keep quests marked as daily.", "keepDaily")
    AddCheck("Keep dungeon quests", "Keep non-trivial dungeon quests.", "keepDungeon")
    AddCheck("…including trivial (10+ levels below)", "Also keep dungeon quests far below your level.", "keepTrivialDungeon", true)
    AddCheck("Keep Path to Ascension quests", "Keep quests related to the Path to Ascension.", "keepAscension")
    AddCheck("Keep quests with progress", "Keep non-trivial quests that have any objective progress.", "keepPartialProgress")
    AddCheck("…including trivial (10+ levels below)", "Also keep in-progress quests far below your level.", "keepTrivialPartialProgress", true)

    -- Whitelist editor.
    local wlLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    wlLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", BASE_X, yPos - 12)
    wlLabel:SetText("Always-keep whitelist (one quest title per line):")

    local wlScroll = CreateFrame("ScrollFrame", "HKSuiteCQScroll", panel, "UIPanelScrollFrameTemplate")
    wlScroll:SetPoint("TOPLEFT", wlLabel, "BOTTOMLEFT", 4, -6)
    wlScroll:SetSize(360, 90)
    wlScroll:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    wlScroll:SetBackdropColor(0, 0, 0, 0.4)

    local wlEdit = CreateFrame("EditBox", "HKSuiteCQEdit", wlScroll)
    wlEdit:SetMultiLine(true)
    wlEdit:SetFontObject(ChatFontNormal)
    wlEdit:SetWidth(340)
    wlEdit:SetAutoFocus(false)
    wlEdit:SetTextInsets(4, 4, 4, 4)
    wlEdit:SetText(table.concat(cfg.whitelist, "\n"))
    local function saveWhitelist(text)
        wipe(cfg.whitelist)
        for line in text:gmatch("[^\r\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then cfg.whitelist[#cfg.whitelist + 1] = line end
        end
    end
    wlEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    wlEdit:SetScript("OnEditFocusLost", function(self) saveWhitelist(self:GetText()) end)
    wlScroll:SetScrollChild(wlEdit)

    local appendBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    appendBtn:SetSize(180, 22)
    appendBtn:SetText("Add current quests")
    appendBtn:SetPoint("TOPLEFT", wlScroll, "BOTTOMLEFT", -4, -8)
    appendBtn:SetScript("OnClick", function()
        local existing = {}
        for _, v in ipairs(cfg.whitelist) do existing[v] = true end
        for i = 1, GetNumQuestLogEntries() do
            local qt, _, _, _, isHeader = GetQuestLogTitle(i)
            if qt and not isHeader and not existing[qt] then
                cfg.whitelist[#cfg.whitelist + 1] = qt
                existing[qt] = true
            end
        end
        wlEdit:SetText(table.concat(cfg.whitelist, "\n"))
    end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("clearquests")
    BuildOptionsPanel()
end
