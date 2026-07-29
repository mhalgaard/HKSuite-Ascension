local ADDON, ns = ...

-- =============================================================================
-- Social module: chat tweaks + group-invite automation.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "social",
    title = "Social",
    desc  = "Class colors, chat tabs, World channel, and group-invite automation.",
    -- Chat tabs are only built on entering the world, so switching the module on
    -- mid-session does nothing visible until a reload.
    reloadOnToggle = true,
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
-- Nudge ElvUI to re-lay-out its chat panel so a re-docked frame appears as a tab
-- rather than floating over the General window.
local function KickElvUIChat()
    if not (ElvUI and ElvUI[1]) then return end
    local CH = ElvUI[1]:GetModule("Chat", true)
    if not CH then return end
    if CH.PositionChat then pcall(CH.PositionChat, CH, true) end
    if CH.UpdateChatTabs then pcall(CH.UpdateChatTabs, CH) end
end

-- Re-dock and show a chat frame that exists but was closed/undocked (e.g. after
-- an ElvUI profile reset wipes the chat layout). Runs even if the frame is
-- currently shown-but-undocked (floating on top of General). pcall'd so an
-- ElvUI dock hook erroring can't break the rest.
local function ShowChatFrame(frame)
    if not frame then return end
    local docked = frame.isDocked
        or (DOCKED_CHAT_FRAMES and tContains(DOCKED_CHAT_FRAMES, frame))
    if not docked and FCF_DockFrame and DOCKED_CHAT_FRAMES then
        pcall(function() frame:SetUserPlaced(false) end)  -- drop any stale floating position
        pcall(FCF_DockFrame, frame, (#DOCKED_CHAT_FRAMES + 1), nil)
    end
    if FCF_SetLocked then pcall(FCF_SetLocked, frame, 1) end
    frame:Show()
    local tab = _G[frame:GetName() .. "Tab"]
    if tab then tab:Show() end
    if FCF_DockUpdate then pcall(FCF_DockUpdate) end
    -- Keep General selected so the re-docked frame sits as a tab, not covering it.
    if ChatFrame1 and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, ChatFrame1) end
    KickElvUIChat()
end

-- Ensure a single tab exists and is visible: create it if missing, or re-open it
-- if it exists but is hidden. Does NOT reconfigure existing tabs (that would wipe
-- any manual tweaks); the "refresh" button does the reconfigure.
local function EnsureOneTab(name, createFn)
    local f = FindChatTab(name)
    if not f then createFn() else ShowChatFrame(f) end
end

local function EnsureTabs()
    if not ns.IsModuleEnabled("social") then return end
    if cfg.enableGuildTab then EnsureOneTab("Guild", CreateGuildTab) end
    if cfg.enableWorldTab then EnsureOneTab("World", CreateWorldTab) end
    if cfg.enableLootTab then EnsureOneTab("Loot", CreateLootTab) end
end

-- Reconfigure an existing World/Loot frame's message groups + channels.
local function ConfigureWorldFrame(frame)
    ChatFrame_RemoveAllMessageGroups(frame)
    AddGroup(frame, "WHISPER")
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
    for _, ch in ipairs(WORLD_CHANNELS) do ChatFrame_AddChannel(frame, ch) end
end

local function ConfigureLootFrame(frame)
    ChatFrame_RemoveAllMessageGroups(frame)
    for _, g in ipairs(LOOT_TAB_GROUPS) do AddGroup(frame, g) end
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
end

-- User-driven: create the enabled tabs, or reconfigure them if they already
-- exist. Verbose so the result is always visible in chat.
local function RefreshTabs(verbose)
    if not ns.IsModuleEnabled("social") then
        if verbose then ns.Print("Social module is disabled.") end
        return
    end

    if not (cfg.enableGuildTab or cfg.enableWorldTab or cfg.enableLootTab) then
        if verbose then ns.Print("No chat tabs are enabled above — tick one first.") end
        return
    end

    if cfg.enableGuildTab then
        local f = FindChatTab("Guild")
        if f then ConfigureGuildFrame(f); ShowChatFrame(f); if verbose then ns.Print("Refreshed & opened \"Guild\" tab.") end
        else CreateGuildTab() end
    end
    if cfg.enableWorldTab then
        local f = FindChatTab("World")
        if f then ConfigureWorldFrame(f); ShowChatFrame(f); if verbose then ns.Print("Refreshed & opened \"World\" tab.") end
        else CreateWorldTab() end
    end
    if cfg.enableLootTab then
        local f = FindChatTab("Loot")
        if f then ConfigureLootFrame(f); ShowChatFrame(f); if verbose then ns.Print("Refreshed & opened \"Loot\" tab.") end
        else CreateLootTab() end
    end
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

function M:BuildSettings(page)
    page:Header("Chat")

    page:Check({
        label = "Always use class colors in all channels",
        tooltip = "Color player names by class in every chat channel.",
        get = function() return cfg.classColors end,
        set = function(v) cfg.classColors = v end,
        onChange = function(on) if on then ApplyClassColors() end end,
    })

    page:Check({
        label = "Auto-join the World channel on login",
        tooltip = "Joins the \"World\" global chat channel automatically when you log in.",
        get = function() return cfg.autoJoinWorld end,
        set = function(v) cfg.autoJoinWorld = v end,
        onChange = function(on)
            if on and GetChannelName("World") == 0 then JoinPermanentChannel("World") end
        end,
    })

    page:Header("Chat tabs")

    local guildTab = page:Check({
        label = "Enable Guild chat tab",
        tooltip = "Creates a \"Guild\" tab if it doesn't exist: all chat messages plus XP, honor, rep, skill-ups, loot, money, system, errors and ignored.",
        get = function() return cfg.enableGuildTab end,
        set = function(v) cfg.enableGuildTab = v end,
        onChange = function(on) if on and not FindChatTab("Guild") then CreateGuildTab() end end,
    })
    guildTab:BindChildren({
        page:Check({
            label = "Only show guild chat & whispers", indent = true,
            tooltip = "When on, the Guild tab shows only guild/officer chat and whispers. When off, it shows the full set. Applies to an existing Guild tab immediately.",
            get = function() return cfg.guildTabOnlyGuild end,
            set = function(v) cfg.guildTabOnlyGuild = v end,
            onChange = function()
                local existing = FindChatTab("Guild")
                if existing then ConfigureGuildFrame(existing) end   -- reconfigure live
            end,
        }),
    })

    page:Check({
        label = "Enable World chat tab",
        tooltip = "Creates a \"World\" tab if it doesn't exist: the Ascension, World, LookingForGroup and Trade channels plus whispers only.",
        get = function() return cfg.enableWorldTab end,
        set = function(v) cfg.enableWorldTab = v end,
        onChange = function(on) if on and not FindChatTab("World") then CreateWorldTab() end end,
    })

    page:Check({
        label = "Enable Loot chat tab",
        tooltip = "Creates a \"Loot\" tab if it doesn't exist: item loot, money, rolls (system) and whispers only.",
        get = function() return cfg.enableLootTab end,
        set = function(v) cfg.enableLootTab = v end,
        onChange = function(on) if on and not FindChatTab("Loot") then CreateLootTab() end end,
    })

    page:Button({
        text = "Create / refresh chat tabs now", width = 240,
        onClick = function() RefreshTabs(true) end,
    })

    page:Spacer(6)
    page:Slider({
        name = "HKSuiteChatFontSlider",
        label = "Chat font size (all tabs)", min = 8, max = 24, step = 1, width = 240,
        get = function() return cfg.fontSize or 12 end,
        set = function(v) cfg.fontSize = v end,
        onChange = ApplyChatFontSize,
    })

    page:Header("Group invites")

    page:Check({
        label = "Auto-accept group invites from friends & guildmates",
        tooltip = "Automatically accept party invites from anyone on your friends list or in your guild.",
        get = function() return cfg.autoAcceptGroup end,
        set = function(v) cfg.autoAcceptGroup = v end,
    })

    local whisperInv = page:Check({
        label = "Auto-invite players who whisper the keyword",
        tooltip = "When someone whispers you the keyword below, automatically invite them to your group.",
        get = function() return cfg.autoInvWhisper end,
        set = function(v) cfg.autoInvWhisper = v end,
    })

    page:Input({
        label = "Keyword", indent = true, width = 140,
        name = "HKSuiteInvKeyword", fallback = "inv",
        get = function() return cfg.autoInvKeyword or "inv" end,
        set = function(v) cfg.autoInvKeyword = (v ~= "" and v) or "inv" end,
    })

    local friendsOnly = page:Check({
        label = "Only from friends & guildmates", indent = true,
        tooltip = "Restrict whisper-invites so only friends and guildmates can be auto-invited.",
        get = function() return cfg.autoInvFriendsOnly end,
        set = function(v) cfg.autoInvFriendsOnly = v end,
    })

    whisperInv:BindChildren({ friendsOnly })
end

function M:OnInit()
    cfg = ns.GetConfig("social")

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
