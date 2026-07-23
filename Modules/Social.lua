local ADDON, ns = ...

-- =============================================================================
-- Social module: chat tweaks + group-invite automation.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "social",
    title = "Social",
    desc  = "Class colors, chat tabs, World channel, and group-invite automation.",
})

ns.defaults.social = {
    -- Chat
    classColors      = true,   -- force class-colored names in every channel
    autoJoinWorld    = true,   -- join the "World" channel on login
    enableGuildTab   = false,  -- ensure a "Guild" tab exists on load
    guildTabOnlyGuild = false, -- Guild tab shows only guild chat + whispers
    enableWorldTab   = false,  -- ensure a "World" tab exists on load
    enableLootTab    = false,  -- ensure a "Loot" tab exists on load
    fontSize         = 12,     -- font size applied to all chat tabs
    -- Group invites
    autoAcceptGroup    = false,  -- accept party invites from friends/guildmates
    autoInvWhisper     = false,  -- invite players who whisper the keyword
    autoInvKeyword     = "inv",  -- the whisper keyword that triggers an invite
    autoInvFriendsOnly = false,  -- restrict whisper-invites to friends/guildmates
}

local cfg  -- filled in OnInit

-- ============================= Class colors ==================================

local function ApplyClassColors()
    -- Enable class coloring for every standard chat-type group (Blizzard's own
    -- toggle, so it persists the same way the chat config checkboxes do).
    for group in pairs(ChatTypeGroup) do
        pcall(ToggleChatColorNamesByClassGroup, true, group)
    end
    -- Belt & suspenders: set the runtime flag on every chat type, including the
    -- numbered channel types (CHANNEL1..n).
    for _, info in pairs(ChatTypeInfo) do
        if type(info) == "table" then
            info.colorNameByClass = true
        end
    end
end

-- Apply a font size to every chat window.
local function ApplyChatFontSize(size)
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then
            if FCF_SetChatWindowFontSize then
                pcall(FCF_SetChatWindowFontSize, nil, cf, size)
            else
                local face, _, flags = cf:GetFont()
                pcall(cf.SetFont, cf, face, size, flags)
            end
        end
    end
end

-- ============================= Tab creation ==================================

-- The full "Chat" category message groups.
local GUILD_CHAT_GROUPS = {
    "SAY", "EMOTE", "YELL",
    "GUILD", "OFFICER", "GUILD_ACHIEVEMENT",
    "WHISPER",
    "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "BATTLEGROUND", "BATTLEGROUND_LEADER",
    "ACHIEVEMENT", "AFK", "DND",
}

-- Selected "Other" category groups the Guild tab should also show.
local GUILD_OTHER_GROUPS = {
    "COMBAT_XP_GAIN",        -- experience
    "COMBAT_HONOR_GAIN",     -- honor
    "COMBAT_FACTION_CHANGE", -- reputation
    "SKILL",                 -- skill ups
    "LOOT",                  -- item loot
    "MONEY",                 -- money loot
    "SYSTEM",                -- system messages
    "ERRORS",                -- errors
    "IGNORED",               -- ignored
}

-- Guild tab when "only guild messages" is enabled.
local GUILD_ONLY_GROUPS = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "WHISPER" }

-- Loot tab: item loot, money, rolls (system) and whispers.
local LOOT_TAB_GROUPS = { "LOOT", "MONEY", "SYSTEM", "WHISPER" }

local WORLD_CHANNELS = { "Ascension", "World", "LookingForGroup", "Trade" }

local function FindChatTab(name)
    for i = 1, NUM_CHAT_WINDOWS do
        local n = GetChatWindowInfo(i)
        if n and n ~= "" and n:lower() == name:lower() then
            return _G["ChatFrame" .. i]
        end
    end
end

local function AddGroup(frame, group)
    if ChatTypeGroup[group] then          -- skip groups this client doesn't have
        ChatFrame_AddMessageGroup(frame, group)
    end
end

local function OpenTab(name)
    local existing = FindChatTab(name)
    if existing then
        ns.Print("A \"" .. name .. "\" tab already exists.")
        return existing, false
    end
    local frame = FCF_OpenNewWindow(name)
    if not frame then frame = FindChatTab(name) end   -- fallback if no return value
    return frame, true
end

-- Apply the Guild tab's message groups based on the "only guild" setting.
-- Split out so toggling the option can reconfigure an existing tab live.
local function ConfigureGuildFrame(frame)
    ChatFrame_RemoveAllMessageGroups(frame)
    if cfg.guildTabOnlyGuild then
        for _, g in ipairs(GUILD_ONLY_GROUPS) do AddGroup(frame, g) end
    else
        for _, g in ipairs(GUILD_CHAT_GROUPS) do AddGroup(frame, g) end
        for _, g in ipairs(GUILD_OTHER_GROUPS) do AddGroup(frame, g) end
    end
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
end

local function CreateGuildTab()
    local frame, created = OpenTab("Guild")
    if not frame then ns.Print("Could not create Guild tab.") return end
    ConfigureGuildFrame(frame)
    if created then ns.Print("Created \"Guild\" tab.") end
end

local function CreateLootTab()
    local frame, created = OpenTab("Loot")
    if not frame then ns.Print("Could not create Loot tab.") return end

    ChatFrame_RemoveAllMessageGroups(frame)
    for _, g in ipairs(LOOT_TAB_GROUPS) do AddGroup(frame, g) end
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end

    if created then ns.Print("Created \"Loot\" tab.") end
end

local function CreateWorldTab()
    local frame, created = OpenTab("World")
    if not frame then ns.Print("Could not create World tab.") return end

    ChatFrame_RemoveAllMessageGroups(frame)
    AddGroup(frame, "WHISPER")
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
    for _, ch in ipairs(WORLD_CHANNELS) do
        ChatFrame_AddChannel(frame, ch)
    end

    if created then
        ns.Print("Created \"World\" tab (join any missing channels to see them).")
    end
end

-- Create the enabled tabs if they don't already exist. Idempotent, so it's safe
-- to run on every login: existing tabs (stored per-character by Blizzard) are
-- left alone; a fresh character with the option enabled gets them made.
local function EnsureTabs()
    if not ns.IsModuleEnabled("social") then return end
    if cfg.enableGuildTab and not FindChatTab("Guild") then CreateGuildTab() end
    if cfg.enableWorldTab and not FindChatTab("World") then CreateWorldTab() end
    if cfg.enableLootTab and not FindChatTab("Loot") then CreateLootTab() end
end

-- =========================== Friends / guildmates ============================

local function EqualsName(a, b)
    return a and b and a:lower() == b:lower()
end

local function IsFriend(name)
    for i = 1, GetNumFriends() do
        if EqualsName(GetFriendInfo(i), name) then return true end
    end
    return false
end

local function IsGuildmate(name)
    if not IsInGuild() then return false end
    for i = 1, GetNumGuildMembers() do
        if EqualsName(GetGuildRosterInfo(i), name) then return true end
    end
    return false
end

local function IsFriendOrGuild(name)
    return IsFriend(name) or IsGuildmate(name)
end

-- ============================= Invite handlers ===============================

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function OnPartyInvite(inviter)
    if not (ns.IsModuleEnabled("social") and cfg.autoAcceptGroup) then return end
    if inviter and IsFriendOrGuild(inviter) then
        AcceptGroup()
        StaticPopup_Hide("PARTY_INVITE")
    end
end

local function OnWhisper(msg, sender)
    if not (ns.IsModuleEnabled("social") and cfg.autoInvWhisper) then return end
    local kw = trim(cfg.autoInvKeyword):lower()
    if kw == "" then return end
    if trim(msg):lower() ~= kw then return end          -- exact keyword match
    if cfg.autoInvFriendsOnly and not IsFriendOrGuild(sender) then return end
    InviteUnit(sender)
end

-- ============================== Options page =================================

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Social"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Social")

    -- ------------------------------------------------------------- Chat section
    local chatHdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    chatHdr:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    chatHdr:SetText("|cffffd100Chat|r")

    local cc = ns.CreateCheck(panel, "Always use class colors in all channels",
        "Color player names by class in every chat channel.", cfg.classColors)
    cc:SetPoint("TOPLEFT", chatHdr, "BOTTOMLEFT", 0, -6)
    cc:SetScript("OnClick", function(self)
        cfg.classColors = self:GetChecked() and true or false
        if cfg.classColors then ApplyClassColors() end
    end)

    local jw = ns.CreateCheck(panel, "Auto-join the World channel on login",
        "Joins the \"World\" global chat channel automatically when you log in.", cfg.autoJoinWorld)
    jw:SetPoint("TOPLEFT", cc, "BOTTOMLEFT", 0, -8)
    jw:SetScript("OnClick", function(self)
        cfg.autoJoinWorld = self:GetChecked() and true or false
        if cfg.autoJoinWorld and GetChannelName("World") == 0 then
            JoinPermanentChannel("World")
        end
    end)

    local gt = ns.CreateCheck(panel, "Enable Guild chat tab",
        "Creates a \"Guild\" tab if it doesn't exist: all chat messages plus XP, honor, rep, skill-ups, loot, money, system, errors and ignored.",
        cfg.enableGuildTab)
    gt:SetPoint("TOPLEFT", jw, "BOTTOMLEFT", 0, -8)
    gt:SetScript("OnClick", function(self)
        cfg.enableGuildTab = self:GetChecked() and true or false
        if cfg.enableGuildTab and not FindChatTab("Guild") then CreateGuildTab() end
    end)

    local go = ns.CreateCheck(panel, "Only show guild chat & whispers",
        "When on, the Guild tab shows only guild/officer chat and whispers. When off, it shows the full set. Applies to an existing Guild tab immediately.",
        cfg.guildTabOnlyGuild)
    go:SetPoint("TOPLEFT", gt, "BOTTOMLEFT", 20, -2)
    go:SetScript("OnClick", function(self)
        cfg.guildTabOnlyGuild = self:GetChecked() and true or false
        local existing = FindChatTab("Guild")
        if existing then ConfigureGuildFrame(existing) end   -- reconfigure live
    end)

    local wt = ns.CreateCheck(panel, "Enable World chat tab",
        "Creates a \"World\" tab if it doesn't exist: the Ascension, World, LookingForGroup and Trade channels plus whispers only.",
        cfg.enableWorldTab)
    wt:SetPoint("TOPLEFT", go, "BOTTOMLEFT", -20, -8)
    wt:SetScript("OnClick", function(self)
        cfg.enableWorldTab = self:GetChecked() and true or false
        if cfg.enableWorldTab and not FindChatTab("World") then CreateWorldTab() end
    end)

    local lt = ns.CreateCheck(panel, "Enable Loot chat tab",
        "Creates a \"Loot\" tab if it doesn't exist: item loot, money, rolls (system) and whispers only.",
        cfg.enableLootTab)
    lt:SetPoint("TOPLEFT", wt, "BOTTOMLEFT", 0, -8)
    lt:SetScript("OnClick", function(self)
        cfg.enableLootTab = self:GetChecked() and true or false
        if cfg.enableLootTab and not FindChatTab("Loot") then CreateLootTab() end
    end)

    local fontSlider = CreateFrame("Slider", "HKSuiteChatFontSlider", panel, "OptionsSliderTemplate")
    fontSlider:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 4, -26)
    fontSlider:SetMinMaxValues(8, 24)
    fontSlider:SetValueStep(1)
    fontSlider:SetWidth(200)
    _G[fontSlider:GetName() .. "Low"]:SetText("8")
    _G[fontSlider:GetName() .. "High"]:SetText("24")
    fontSlider:SetValue(cfg.fontSize or 12)   -- set before wiring OnValueChanged
    _G[fontSlider:GetName() .. "Text"]:SetText("Chat font size (all tabs): " .. (cfg.fontSize or 12))
    fontSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        cfg.fontSize = value
        _G[self:GetName() .. "Text"]:SetText("Chat font size (all tabs): " .. value)
        ApplyChatFontSize(value)
    end)

    -- ---------------------------------------------------- Group invites section
    local invHdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    invHdr:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", -4, -22)
    invHdr:SetText("|cffffd100Group Invites|r")

    local ag = ns.CreateCheck(panel, "Auto-accept group invites from friends & guildmates",
        "Automatically accept party invites from anyone on your friends list or in your guild.", cfg.autoAcceptGroup)
    ag:SetPoint("TOPLEFT", invHdr, "BOTTOMLEFT", 0, -6)
    ag:SetScript("OnClick", function(self) cfg.autoAcceptGroup = self:GetChecked() and true or false end)

    local iw = ns.CreateCheck(panel, "Auto-invite players who whisper the keyword",
        "When someone whispers you the keyword below, automatically invite them to your group.", cfg.autoInvWhisper)
    iw:SetPoint("TOPLEFT", ag, "BOTTOMLEFT", 0, -8)

    local kwLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    kwLabel:SetPoint("TOPLEFT", iw, "BOTTOMLEFT", 20, -10)
    kwLabel:SetText("Keyword:")

    local kw = CreateFrame("EditBox", "HKSuiteInvKeyword", panel, "InputBoxTemplate")
    kw:SetSize(120, 20)
    kw:SetPoint("LEFT", kwLabel, "RIGHT", 12, 0)
    kw:SetAutoFocus(false)
    kw:SetText(cfg.autoInvKeyword or "inv")
    kw:SetScript("OnEnterPressed", function(self) cfg.autoInvKeyword = self:GetText() self:ClearFocus() end)
    kw:SetScript("OnEscapePressed", function(self) self:SetText(cfg.autoInvKeyword or "inv") self:ClearFocus() end)

    local fo = ns.CreateCheck(panel, "Only from friends & guildmates",
        "Restrict whisper-invites so only friends and guildmates can be auto-invited.", cfg.autoInvFriendsOnly)
    fo:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", -20, -8)
    fo:SetScript("OnClick", function(self) cfg.autoInvFriendsOnly = self:GetChecked() and true or false end)

    -- Grey the whisper sub-options while whisper-invite is off (still clickable).
    local function RefreshInv()
        local c = cfg.autoInvWhisper and 1 or 0.5
        kwLabel:SetTextColor(c, c, c)
        fo.label:SetTextColor(c, c, c)
    end
    iw:SetScript("OnClick", function(self)
        cfg.autoInvWhisper = self:GetChecked() and true or false
        RefreshInv()
    end)
    RefreshInv()

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.GetConfig("social")
    BuildOptionsPanel()

    if IsInGuild() then GuildRoster() end   -- request roster so guild checks work
    ShowFriends()                            -- request friends list

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PARTY_INVITE_REQUEST")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "PLAYER_ENTERING_WORLD" then
            if not ns.IsModuleEnabled("social") then return end
            if cfg.classColors then ApplyClassColors() end
            ApplyChatFontSize(cfg.fontSize or 12)
            if cfg.autoJoinWorld and GetChannelName("World") == 0 then
                JoinPermanentChannel("World")   -- idempotent
            end
            EnsureTabs()
            if IsInGuild() then GuildRoster() end
        elseif event == "PARTY_INVITE_REQUEST" then
            OnPartyInvite(arg1)                 -- arg1 = inviter name
        elseif event == "CHAT_MSG_WHISPER" then
            OnWhisper(arg1, arg2)               -- arg1 = message, arg2 = sender
        end
    end)
end
