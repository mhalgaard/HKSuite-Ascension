local ADDON, ns = ...

local M = ns.RegisterModule({
    key   = "quest",
    title = "Quest Automation",
    desc  = "Automatically accept, hand in, and pick rewards for quests.",
})

-- Defaults for this module. Registered before Core merges SavedVariables.
ns.defaults.quest = {
    autoAccept       = true,   -- accept offered quests automatically
    autoTurnIn       = false,  -- hand in completed quests automatically
    autoSelectReward = false,  -- pick the highest-vendor-value reward, then hand in
    autoSkipGossip   = false,  -- auto-select a lone gossip option to skip the talk menu
    skipDailies      = false,  -- don't auto-accept daily quests
    autoAcceptCallboard = false, -- auto-accept callboard / command board quests
    bypassModifier   = "SHIFT", -- hold this to temporarily disable: SHIFT / CTRL / ALT / NONE
}

local cfg  -- filled in OnInit

-- The callboard / command board is a specific quest giver we treat separately.
local CALLBOARD_NAMES = { "callboard", "command board" }
local function IsCallboard()
    local name = (UnitName("npc") or UnitName("target") or ""):lower()
    for _, n in ipairs(CALLBOARD_NAMES) do
        if name:find(n, 1, true) then return true end
    end
    return false
end

-- True while the player holds the configured bypass key, so they can
-- interact with quest givers manually without automation kicking in.
local function BypassHeld()
    local m = cfg.bypassModifier
    if m == "SHIFT" then return IsShiftKeyDown()
    elseif m == "CTRL" then return IsControlKeyDown()
    elseif m == "ALT" then return IsAltKeyDown() end
    return false
end

-- Should we drive a quest all the way to delivery?
local function ShouldDeliver()
    return cfg.autoTurnIn or cfg.autoSelectReward
end

-- Vendor value of quest reward choice `i` (sell price * stack size).
-- Returns 0 when the item isn't cached yet.
local function RewardValue(i)
    local link = GetQuestItemLink("choice", i)
    if not link then return 0 end
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
    if not sellPrice then return 0 end
    local _, _, numItems = GetQuestItemInfo("choice", i)
    return sellPrice * (numItems or 1)
end

-- Index of the most valuable reward choice.
local function BestReward()
    local best, bestVal = 1, -1
    for i = 1, GetNumQuestChoices() do
        local v = RewardValue(i)
        if v > bestVal then bestVal, best = v, i end
    end
    return best
end

local handlers = {}

-- Guard against accepting the same quest twice in quick succession. Some NPCs
-- re-show a just-accepted quest before their list refreshes, which otherwise
-- triggers a redundant AcceptQuest() and a "You are already on that quest" error.
local lastQuestTitle, lastQuestTime = nil, 0

function handlers.QUEST_DETAIL()
    if not cfg.autoAccept or BypassHeld() then return end
    if cfg.skipDailies and QuestIsDaily and QuestIsDaily() then return end
    if IsCallboard() and not cfg.autoAcceptCallboard then return end
    local title = GetTitleText()
    local now = GetTime()
    if title and title == lastQuestTitle and (now - lastQuestTime) < 1.5 then
        return  -- already accepted this one moments ago; skip the duplicate
    end
    lastQuestTitle, lastQuestTime = title, now
    AcceptQuest()
end

function handlers.QUEST_ACCEPT_CONFIRM()
    if cfg.autoAccept and not BypassHeld() then
        ConfirmAcceptQuest()
    end
end

function handlers.QUEST_PROGRESS()
    if ShouldDeliver() and not BypassHeld() and IsQuestCompletable() then
        CompleteQuest()
    end
end

function handlers.QUEST_COMPLETE()
    if BypassHeld() then return end
    local numChoices = GetNumQuestChoices()
    if numChoices > 1 then
        if cfg.autoSelectReward then
            GetQuestReward(BestReward())
        end
    else
        if ShouldDeliver() then
            GetQuestReward(1)
        end
    end
end

function handlers.QUEST_GREETING()
    if BypassHeld() then return end
    if ShouldDeliver() then
        for i = 1, GetNumActiveQuests() do
            SelectActiveQuest(i)
        end
    end
    if cfg.autoAccept and not (IsCallboard() and not cfg.autoAcceptCallboard) then
        for i = 1, GetNumAvailableQuests() do
            SelectAvailableQuest(i)
        end
    end
end

function handlers.GOSSIP_SHOW()
    if BypassHeld() then return end
    if cfg.autoAccept and not (IsCallboard() and not cfg.autoAcceptCallboard) then
        for i = 1, GetNumGossipAvailableQuests() do
            SelectGossipAvailableQuest(i)
        end
    end
    if ShouldDeliver() then
        local num = GetNumGossipActiveQuests()
        if num > 0 then
            local data = { GetGossipActiveQuests() }
            local fields = #data / num          -- field count varies by build
            for i = 1, num do
                local isComplete = data[(i - 1) * fields + 4]  -- isComplete is 4th
                if isComplete then
                    SelectGossipActiveQuest(i)
                    break
                end
            end
        end
    end
    -- Skip the talk menu when the NPC has no quests to handle and exactly one
    -- gossip option, so we go straight to it (vendor, flight master, etc.).
    if cfg.autoSkipGossip
        and GetNumGossipAvailableQuests() == 0
        and GetNumGossipActiveQuests() == 0
        and GetNumGossipOptions() == 1 then
        SelectGossipOption(1)
    end
end

-- Settings sub-page nested under the Overview.
local BYPASS_KEYS = { "NONE", "SHIFT", "CTRL", "ALT" }
local BYPASS_LABEL = { NONE = "None", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" }

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Quest Automation"
    panel.parent = "HKSuite"   -- nest under the Overview page

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Quest Automation")

    local accept = ns.CreateCheck(panel, "Auto-accept quests",
        "Automatically accept quests offered by NPCs (including shared/escort confirmations).",
        cfg.autoAccept)
    accept:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    accept:SetScript("OnClick", function(self)
        cfg.autoAccept = self:GetChecked() and true or false
    end)

    local turnIn = ns.CreateCheck(panel, "Auto turn in quests",
        "Automatically hand in completed quests. On quests with a choice of rewards, waits for you to pick unless the sub-option below is enabled.",
        cfg.autoTurnIn)
    turnIn:SetPoint("TOPLEFT", accept, "BOTTOMLEFT", 0, -8)

    local reward = ns.CreateCheck(panel, "Auto-select most valuable reward",
        "On quests with multiple reward choices, automatically pick the highest vendor-value reward. Enabling this also enables Auto turn in.",
        cfg.autoSelectReward)
    reward:SetPoint("TOPLEFT", turnIn, "BOTTOMLEFT", 20, -2)

    local function RefreshChild()
        reward.label:SetTextColor(cfg.autoTurnIn and 1 or 0.5,
                                  cfg.autoTurnIn and 1 or 0.5,
                                  cfg.autoTurnIn and 1 or 0.5)
    end

    turnIn:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        cfg.autoTurnIn = on
        if not on then
            cfg.autoSelectReward = false
            reward:SetChecked(false)
        end
        RefreshChild()
    end)

    reward:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        cfg.autoSelectReward = on
        if on then
            cfg.autoTurnIn = true
            turnIn:SetChecked(true)
        end
        RefreshChild()
    end)

    RefreshChild()

    local skipGossip = ns.CreateCheck(panel, "Auto-skip single gossip option",
        "When an NPC greets you with just one gossip option and no quests to handle, select it automatically to skip the talk menu.",
        cfg.autoSkipGossip)
    skipGossip:SetPoint("TOPLEFT", reward, "BOTTOMLEFT", -20, -8)  -- back to base indent
    skipGossip:SetScript("OnClick", function(self)
        cfg.autoSkipGossip = self:GetChecked() and true or false
    end)

    local skipDaily = ns.CreateCheck(panel, "Don't auto-accept daily quests",
        "Skips auto-accepting quests flagged as daily. You can still accept them manually.",
        cfg.skipDailies)
    skipDaily:SetPoint("TOPLEFT", skipGossip, "BOTTOMLEFT", 0, -8)
    skipDaily:SetScript("OnClick", function(self)
        cfg.skipDailies = self:GetChecked() and true or false
    end)

    local callboard = ns.CreateCheck(panel, "Auto-accept callboard / command board quests",
        "By default, quests from the callboard / command board are NOT auto-accepted. Enable this to auto-accept them too.",
        cfg.autoAcceptCallboard)
    callboard:SetPoint("TOPLEFT", skipDaily, "BOTTOMLEFT", 0, -8)
    callboard:SetScript("OnClick", function(self)
        cfg.autoAcceptCallboard = self:GetChecked() and true or false
    end)

    local bypassLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bypassLabel:SetPoint("TOPLEFT", callboard, "BOTTOMLEFT", 0, -18)
    bypassLabel:SetText("Hold key to pause automation:")

    local dropdown = CreateFrame("Frame", "HKSuiteBypassDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", bypassLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(dropdown, 90)
    UIDropDownMenu_SetText(dropdown, BYPASS_LABEL[cfg.bypassModifier] or "None")
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, k in ipairs(BYPASS_KEYS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = BYPASS_LABEL[k]
            info.value = k
            info.checked = (cfg.bypassModifier == k)
            info.func = function(button)
                cfg.bypassModifier = button.value
                UIDropDownMenu_SetText(dropdown, BYPASS_LABEL[button.value])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("quest")

    -- Reward selection can only deliver if turn-in is on, so keep them in sync.
    if cfg.autoSelectReward then cfg.autoTurnIn = true end

    local frame = CreateFrame("Frame")
    for event in pairs(handlers) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if ns.IsModuleEnabled("quest") then   -- respect the Overview toggle
            handlers[event](...)
        end
    end)

    BuildOptionsPanel()
end
