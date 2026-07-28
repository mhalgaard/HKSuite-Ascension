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
    autoShareQuests  = false,  -- share quests with the party automatically when accepted
    shareOnlyInParty = true,   -- ...but never while in a raid
    autoOpenInProgress = false, -- lowest priority: open quests already in your log
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

-- Is the quest with this title flagged complete in our quest log? The greeting
-- frame gives us no completion info at all, and the gossip flag's position moves
-- between builds, so the log is our source of truth.
-- Collapsed headers hide their quests from GetQuestLogTitle, so on a miss expand
-- everything and look once more before giving up.
local function LogQuestComplete(title, retried)
    if not title then return false end
    local sawCollapsed = false
    for i = 1, GetNumQuestLogEntries() do
        local t, _, _, _, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
        if isHeader then
            if isCollapsed then sawCollapsed = true end
        elseif t == title then
            return isComplete == 1   -- 1 = complete, -1 = failed, nil = in progress
        end
    end
    if sawCollapsed and not retried then
        ExpandQuestHeader(0)         -- 0 = all headers
        return LogQuestComplete(title, true)
    end
    return false
end

-- Normalise GetGossipActiveQuests() into { index, title, complete } records.
-- It returns a flat run of fields per quest and the field count varies by build,
-- so derive it with select("#") (trailing nils make #{...} unreliable) and take
-- isComplete from the last field of each record, OR'd with the quest log.
local function GossipActiveQuests()
    local num = GetNumGossipActiveQuests()
    if num == 0 then return {} end
    local count = select("#", GetGossipActiveQuests())
    local data = { GetGossipActiveQuests() }
    local fields = math.floor(count / num)
    local out = {}
    for i = 1, num do
        local base = (i - 1) * fields
        local title = data[base + 1]
        local complete = data[base + fields] and true or false
        out[i] = {
            index    = i,
            title    = title,
            complete = complete or LogQuestComplete(title),
        }
    end
    return out
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

-- Fired when a quest is added to the log; arg1 is its quest-log index.
function handlers.QUEST_ACCEPTED(questIndex)
    if not cfg.autoShareQuests or BypassHeld() then return end
    if not questIndex then return end
    -- GetNumRaidMembers() is the unambiguous raid test: 0 outside a raid, and it
    -- doesn't depend on what GetNumPartyMembers() reports for your subgroup.
    local inRaid = GetNumRaidMembers() > 0
    if not inRaid and GetNumPartyMembers() == 0 then return end
    if inRaid and cfg.shareOnlyInParty then return end
    SelectQuestLogEntry(questIndex)
    -- GetQuestLogPushable() reflects the selected quest; skip un-shareable ones
    -- so we don't spew "that quest can't be shared" errors.
    if GetQuestLogPushable and not GetQuestLogPushable() then return end
    QuestLogPushQuest()
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

-- May we take new quests from whoever we're talking to right now?
local function CanAcceptHere()
    return cfg.autoAccept and not (IsCallboard() and not cfg.autoAcceptCallboard)
end

-- Both quest-giver frames pick exactly ONE thing per showing, in this order:
--   1. hand in a completed quest
--   2. accept an available quest
--   3. open a quest that's already in the log but unfinished (opt-in)
-- The first Select* call swaps the frame out from under us, so anything after it
-- would be acting on a stale menu. The NPC re-shows its list once we're done with
-- that quest, which re-fires the event and drains the next item on the next pass.

-- Classic quest-list frame (no gossip menu).
function handlers.QUEST_GREETING()
    if BypassHeld() then return end

    if ShouldDeliver() then
        for i = 1, GetNumActiveQuests() do
            if LogQuestComplete(GetActiveTitle(i)) then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if CanAcceptHere() and GetNumAvailableQuests() > 0 then
        SelectAvailableQuest(1)
        return
    end

    if cfg.autoOpenInProgress and GetNumActiveQuests() > 0 then
        SelectActiveQuest(1)
    end
end

-- Debounce: GOSSIP_SHOW and QUEST_FINISHED can land in the same frame for one
-- menu, and acting twice would select against a stale list. GetTime() is frame
-- granular, so this only swallows same-frame duplicates, not a genuine re-show.
local lastGossipTime = 0

local function HandleGossip()
    if BypassHeld() then return end
    local now = GetTime()
    if (now - lastGossipTime) < 0.05 then return end
    lastGossipTime = now

    local active = GossipActiveQuests()

    if ShouldDeliver() then
        for _, q in ipairs(active) do
            if q.complete then
                SelectGossipActiveQuest(q.index)
                return
            end
        end
    end

    if CanAcceptHere() and GetNumGossipAvailableQuests() > 0 then
        SelectGossipAvailableQuest(1)
        return
    end

    if cfg.autoOpenInProgress then
        for _, q in ipairs(active) do
            if not q.complete then
                SelectGossipActiveQuest(q.index)
                return
            end
        end
    end

    -- Nothing quest-related left: skip the talk menu when the NPC has exactly one
    -- gossip option, so we go straight to it (vendor, flight master, etc.).
    if cfg.autoSkipGossip
        and GetNumGossipAvailableQuests() == 0
        and GetNumGossipActiveQuests() == 0
        and GetNumGossipOptions() == 1 then
        SelectGossipOption(1)
    end
end

function handlers.GOSSIP_SHOW()
    HandleGossip()
end

-- Finished with one quest. If the NPC left its gossip menu up instead of re-firing
-- GOSSIP_SHOW, run the priority pass again so the rest of its list still drains.
function handlers.QUEST_FINISHED()
    if GossipFrame and GossipFrame:IsShown() then
        HandleGossip()
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

    local inProgress = ns.CreateCheck(panel, "Also open quests already in your log",
        "Lowest priority. After completed hand-ins and new quests are dealt with, open a quest you're already on (shows its progress text). Leave off if quest givers double as vendors.",
        cfg.autoOpenInProgress)
    inProgress:SetPoint("TOPLEFT", reward, "BOTTOMLEFT", -20, -8)  -- back to base indent
    inProgress:SetScript("OnClick", function(self)
        cfg.autoOpenInProgress = self:GetChecked() and true or false
    end)

    local skipGossip = ns.CreateCheck(panel, "Auto-skip single gossip option",
        "When an NPC greets you with just one gossip option and no quests to handle, select it automatically to skip the talk menu.",
        cfg.autoSkipGossip)
    skipGossip:SetPoint("TOPLEFT", inProgress, "BOTTOMLEFT", 0, -8)
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

    local share = ns.CreateCheck(panel, "Auto-share quests with your party",
        "When you accept a quest, automatically share it with your party (only quests that can be shared).",
        cfg.autoShareQuests)
    share:SetPoint("TOPLEFT", callboard, "BOTTOMLEFT", 0, -8)

    local partyOnly = ns.CreateCheck(panel, "Party only — never share in a raid",
        "Only auto-share while in a normal party. In a raid group, quests are never shared automatically.",
        cfg.shareOnlyInParty)
    partyOnly:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 20, -2)

    local function RefreshShareChild()
        local on = cfg.autoShareQuests
        partyOnly.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end

    share:SetScript("OnClick", function(self)
        cfg.autoShareQuests = self:GetChecked() and true or false
        RefreshShareChild()
    end)

    partyOnly:SetScript("OnClick", function(self)
        cfg.shareOnlyInParty = self:GetChecked() and true or false
    end)

    RefreshShareChild()

    local bypassLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bypassLabel:SetPoint("TOPLEFT", partyOnly, "BOTTOMLEFT", -20, -18)
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
