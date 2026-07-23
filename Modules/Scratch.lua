local ADDON, ns = ...

-- =============================================================================
-- PROTOTYPE: Social module
-- Chat tweaks + group-invite automation. Developed here for /reload testing;
-- promote to Modules/Social.lua when finalized.
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

    -- ---------------------------------------------------- Group invites section
    local invHdr = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    invHdr:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -16)
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
    cfg = ns.config.social
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

-- =============================================================================
-- PROTOTYPE: System module
-- Wrapped in do...end so its locals don't collide with the Chat prototype above.
-- CVars modelled on Leatrix Plus.
-- =============================================================================
do
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
end

-- =============================================================================
-- PROTOTYPE: Loot Auto Roller module
-- Standard group-loot API (START_LOOT_ROLL / RollOnLoot / CONFIRM_LOOT_ROLL).
-- Ascension adds quality 6 ("Vanity", gold), which is included below.
-- =============================================================================
do
    local M = ns.RegisterModule({
        key   = "lootroll",
        title = "Loot Auto Roller",
        desc  = "Automatically pass/greed/disenchant/need on loot rolls, by item quality.",
        defaultEnabled = false,
    })

    ns.defaults.lootroll = {
        rollOnBoP = false,   -- when off, BoP items are left for manual rolling
        quality = {
            [0] = "greed",   -- Poor
            [1] = "greed",   -- Common
            [2] = "greed",   -- Uncommon
            [3] = "none",    -- Rare
            [4] = "none",    -- Epic
            [5] = "none",    -- Legendary
            [6] = "greed",   -- Vanity (Ascension)
        },
    }

    local cfg
    local autoRolled = {}    -- rollIDs we initiated, so we only auto-confirm our own

    -- Decide and cast the roll for a given rollID.
    local function DoRoll(rollID)
        if not ns.IsModuleEnabled("lootroll") then return end
        local _, _, _, quality, bop, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
        if quality == nil then return end

        local action = cfg.quality[quality]
        if not action or action == "none" then return end
        if bop and not cfg.rollOnBoP then return end   -- BoP protection

        local rollType
        if action == "pass" then
            rollType = 0
        elseif action == "need" then
            rollType = canNeed and 1 or (canGreed and 2 or 0)          -- fall back to greed, then pass
        elseif action == "greed" then
            rollType = canGreed and 2 or 0
        elseif action == "disenchant" then
            rollType = canDisenchant and 3 or (canGreed and 2 or 0)    -- fall back to greed, then pass
        else
            return
        end

        autoRolled[rollID] = true
        RollOnLoot(rollID, rollType)
    end

    -- ---------------------------------------------------------------- Options UI
    local QUALITY_ORDER = { 0, 1, 2, 3, 4, 5, 6 }
    local QUALITY_NAMES = {
        [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
        [4] = "Epic", [5] = "Legendary", [6] = "Vanity",
    }
    local ROLL_OPTIONS = {
        { value = "none",       text = "No auto-roll" },
        { value = "pass",       text = "Pass" },
        { value = "greed",      text = "Greed" },
        { value = "disenchant", text = "Disenchant" },
        { value = "need",       text = "Need" },
    }
    local ROLL_LABEL = {}
    for _, o in ipairs(ROLL_OPTIONS) do ROLL_LABEL[o.value] = o.text end

    local function QualityColor(q)
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end

    local function BuildOptionsPanel()
        local panel = CreateFrame("Frame")
        panel.name = "Loot Auto Roller"
        panel.parent = "HKSuite"

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Loot Auto Roller")

        local bop = ns.CreateCheck(panel, "Also auto-roll on Bind-on-Pickup items",
            "When off (default), BoP items are left for you to roll manually.", cfg.rollOnBoP)
        bop:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        bop:SetScript("OnClick", function(self) cfg.rollOnBoP = self:GetChecked() and true or false end)

        local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", bop, "BOTTOMLEFT", 4, -12)
        hint:SetText("Action per item quality:")

        local anchor = hint
        for _, q in ipairs(QUALITY_ORDER) do
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(320, 28)
            row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, (anchor == hint) and -6 or -4)

            local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetPoint("LEFT", row, "LEFT", 4, 0)
            label:SetWidth(90)
            label:SetJustifyH("LEFT")
            label:SetText(QUALITY_NAMES[q])
            label:SetTextColor(QualityColor(q))

            local dd = CreateFrame("Frame", "HKSuiteRollDD" .. q, row, "UIDropDownMenuTemplate")
            dd:SetPoint("LEFT", label, "RIGHT", -6, 0)
            UIDropDownMenu_SetWidth(dd, 110)
            UIDropDownMenu_SetText(dd, ROLL_LABEL[cfg.quality[q]] or "No auto-roll")
            UIDropDownMenu_Initialize(dd, function(self, level)
                for _, opt in ipairs(ROLL_OPTIONS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt.text
                    info.value = opt.value
                    info.checked = (cfg.quality[q] == opt.value)
                    info.func = function(btn)
                        cfg.quality[q] = btn.value
                        UIDropDownMenu_SetText(dd, ROLL_LABEL[btn.value])
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)

            anchor = row
        end

        InterfaceOptions_AddCategory(panel)
    end

    function M:OnInit()
        cfg = ns.config.lootroll
        BuildOptionsPanel()

        local f = CreateFrame("Frame")
        f:RegisterEvent("START_LOOT_ROLL")
        f:RegisterEvent("CONFIRM_LOOT_ROLL")
        f:SetScript("OnEvent", function(_, event, id, rollType)
            if event == "START_LOOT_ROLL" then
                DoRoll(id)
            elseif event == "CONFIRM_LOOT_ROLL" then
                if autoRolled[id] then          -- only confirm rolls we cast
                    ConfirmLootRoll(id, rollType)
                    autoRolled[id] = nil
                end
            end
        end)
    end
end

-- =============================================================================
-- PROTOTYPE: Auto Summon Premium Pets module
-- Faithful port of the Ascension WeakAura (rev 17). Exception requested by user:
-- Wondrous Wisdomball is only summoned in NORMAL-difficulty dungeons.
-- =============================================================================
do
    local M = ns.RegisterModule({
        key   = "pets",
        title = "Auto Summon Premium Pets",
        desc  = "Summons the right premium pet for your current context.",
        defaultEnabled = false,
    })

    ns.defaults.pets = {
        recastDelay    = 8,       -- seconds between summon attempts (0-600)
        summonInCombat = false,   -- allow summoning while in combat
        noResummon     = false,   -- only summon after a zone change
        lootTrans      = false,   -- skip Lootbot if Loot-Transfigurator is owned
        safeZonePet    = "",      -- preferred pet name in rest/AFK zones
    }

    local cfg

    -- State
    local lastSummonTime   = 0
    local lastSummonedZone = nil
    local dungeonEnterTime = nil
    local lfgCompleteTime  = nil
    local lfgEverCompleted = false

    -- Scheduling helpers (Ascension provides C_Timer; fall back just in case).
    local function afterDelay(delay, fn)
        if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
    end
    local function startTicker(interval, fn)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(interval, fn)
        else
            local acc, t = 0, CreateFrame("Frame")
            t:SetScript("OnUpdate", function(_, e)
                acc = acc + e
                if acc >= interval then acc = 0 fn() end
            end)
        end
    end

    -- State helpers
    local function hasAura(fn, name)
        for i = 1, 40 do
            local n = fn("player", i)
            if not n then break end
            if n == name then return true end
        end
        return false
    end
    local function hasBuff(name)   return hasAura(UnitBuff, name) end
    local function hasDebuff(name) return hasAura(UnitDebuff, name) end

    local function isCasting()
        return UnitCastingInfo("player") or UnitChannelInfo("player")
    end

    local function inManastorm()
        if C_Manastorm and C_Manastorm.IsInManastorm then
            local ok, res = pcall(C_Manastorm.IsInManastorm)
            return ok and res
        end
        return false
    end

    local function currentZoneToken()
        return (GetZoneText() or "") .. "|" .. (GetSubZoneText() or "")
    end

    -- Companion lookup (name substring match, like the WeakAura).
    local function findPetIndex(name)
        for i = 1, GetNumCompanions("CRITTER") do
            local _, cname = GetCompanionInfo("CRITTER", i)
            if cname and cname:find(name, 1, true) then
                return i, cname
            end
        end
    end

    local function summonPet(idx)
        lastSummonTime = GetTime()
        lastSummonedZone = currentZoneToken()
        afterDelay(0.2, function() CallCompanion("CRITTER", idx) end)
    end

    local function canAttemptSummon()
        if UnitIsDeadOrGhost("player") then return false end
        if IsMounted() then return false end
        if isCasting() then return false end
        if IsStealthed() or hasBuff("Invisibility") or hasBuff("Mass Invisibility") then return false end
        if hasDebuff("Smite Stomp") then return false end
        if UnitAffectingCombat("player") and not cfg.summonInCombat then return false end

        local _, instanceType = GetInstanceInfo()
        if instanceType == "arena" or instanceType == "pvp" then return false end   -- no pet in PvP

        if (GetTime() - lastSummonTime) < (cfg.recastDelay or 8) then return false end

        if cfg.noResummon and lastSummonedZone == currentZoneToken() then return false end

        return true
    end

    local function buildPriorityList()
        -- Manastorm: Cogsley (ideally with the Eye buff) then Lootbot.
        if inManastorm() then
            return { "Cogsley", "Lootbot 3000" }
        end

        local _, instanceType, difficultyIndex = GetInstanceInfo()
        if IsInInstance() then
            if instanceType == "party" then
                local list = {}
                -- Wisdomball ONLY in Normal dungeons (difficultyIndex 1), and only
                -- in the first 15s of the run or just after an LFG completion.
                if difficultyIndex == 1 then
                    local recent = dungeonEnterTime and (GetTime() - dungeonEnterTime) <= 15
                    local postLFG = lfgCompleteTime and (GetTime() - lfgCompleteTime) <= 60
                    if recent or postLFG then
                        table.insert(list, "Wondrous Wisdomball")
                    end
                end
                table.insert(list, "Lootbot 3000")
                return list
            elseif instanceType == "raid" then
                return { "Lootbot 3000" }
            end
        end

        -- Safe zone (resting / AFK): custom pet then Book.
        if IsResting() or UnitIsAFK("player") then
            local list = {}
            if cfg.safeZonePet and cfg.safeZonePet ~= "" then table.insert(list, cfg.safeZonePet) end
            table.insert(list, "Book of Ascension")
            return list
        end

        -- Open world. While still leveling (before first LFG completion), the WA
        -- prefers the Book; otherwise Lootbot leads.
        local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 80
        local leveling = UnitLevel("player") < maxLevel and not lfgEverCompleted
        local list
        if leveling then
            list = { "Book of Ascension", "Lootbot 3000", "Treasure Keeper", "Fix-o-Tron" }
        else
            list = { "Lootbot 3000", "Book of Ascension", "Treasure Keeper", "Fix-o-Tron" }
        end
        if cfg.lootTrans and findPetIndex("Loot-Transfigurator") then
            table.remove(list, 1)   -- drop Lootbot if the Transfigurator is owned
        end
        return list
    end

    local function choosePet()
        if not ns.IsModuleEnabled("pets") then return end
        if not canAttemptSummon() then return end

        for _, petName in ipairs(buildPriorityList()) do
            local idx = findPetIndex(petName)
            if idx then
                local _, _, _, _, active = GetCompanionInfo("CRITTER", idx)
                if active then
                    return          -- best owned pet already out
                else
                    summonPet(idx)  -- summon the highest-priority owned pet
                    return
                end
            end
        end
    end

    -- ---------------------------------------------------------------- Options UI
    local function BuildOptionsPanel()
        local panel = CreateFrame("Frame")
        panel.name = "Auto Summon Premium Pets"
        panel.parent = "HKSuite"

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Auto Summon Premium Pets")

        local combat = ns.CreateCheck(panel, "Summon while in combat",
            "Allow summoning premium pets during combat.", cfg.summonInCombat)
        combat:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        combat:SetScript("OnClick", function(self) cfg.summonInCombat = self:GetChecked() and true or false end)

        local noResum = ns.CreateCheck(panel, "Only summon after a zone change",
            "Avoids re-summoning until you move to a different zone.", cfg.noResummon)
        noResum:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -8)
        noResum:SetScript("OnClick", function(self) cfg.noResummon = self:GetChecked() and true or false end)

        local lootT = ns.CreateCheck(panel, "Skip Lootbot if Loot-Transfigurator is owned",
            "Removes Lootbot 3000 from the priority when you own the Loot-Transfigurator.", cfg.lootTrans)
        lootT:SetPoint("TOPLEFT", noResum, "BOTTOMLEFT", 0, -8)
        lootT:SetScript("OnClick", function(self) cfg.lootTrans = self:GetChecked() and true or false end)

        local slider = CreateFrame("Slider", "HKSuitePetDelaySlider", panel, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", lootT, "BOTTOMLEFT", 4, -28)
        slider:SetMinMaxValues(0, 600)
        slider:SetValueStep(1)
        slider:SetWidth(220)
        _G[slider:GetName() .. "Low"]:SetText("0")
        _G[slider:GetName() .. "High"]:SetText("600")
        _G[slider:GetName() .. "Text"]:SetText("Recast delay: " .. (cfg.recastDelay or 8) .. "s")
        slider:SetValue(cfg.recastDelay or 8)
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            cfg.recastDelay = value
            _G[self:GetName() .. "Text"]:SetText("Recast delay: " .. value .. "s")
        end)

        local ebLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        ebLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -24)
        ebLabel:SetText("Safe-zone pet (name):")

        local eb = CreateFrame("EditBox", "HKSuitePetSafeZone", panel, "InputBoxTemplate")
        eb:SetSize(180, 20)
        eb:SetPoint("LEFT", ebLabel, "RIGHT", 12, 0)
        eb:SetAutoFocus(false)
        eb:SetText(cfg.safeZonePet or "")
        eb:SetScript("OnEnterPressed", function(self) cfg.safeZonePet = self:GetText() self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:SetText(cfg.safeZonePet or "") self:ClearFocus() end)

        InterfaceOptions_AddCategory(panel)
    end

    function M:OnInit()
        cfg = ns.config.pets
        BuildOptionsPanel()

        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("LFG_COMPLETION_REWARD")
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                local _, itype = GetInstanceInfo()
                if IsInInstance() and itype == "party" then
                    dungeonEnterTime = GetTime()
                end
            elseif event == "LFG_COMPLETION_REWARD" then
                lfgCompleteTime = GetTime()
                lfgEverCompleted = true
            end
        end)

        startTicker(2, choosePet)   -- matches the WeakAura's 2-second cadence
    end
end

-- =============================================================================
-- PROTOTYPE: Addon Button module
-- A movable square "HK" button and/or CTRL+click on the minimap open a flyout
-- that consolidates other addons' minimap buttons.
-- =============================================================================
do
    local M = ns.RegisterModule({
        key   = "addonbutton",
        title = "Addon Button",
        desc  = "Consolidates addon minimap buttons into one HK flyout menu.",
    })

    ns.defaults.addonbutton = {
        showButton = true,   -- show the movable HK button
        buttonPos  = false,  -- {point, relPoint, x, y} once the user moves it
    }

    local cfg
    local button, menu
    local collected, collectedSet = {}, {}

    -- Blizzard minimap frames we never want to pull into the menu.
    local IGNORE = {
        MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
        MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
        MiniMapMailFrame = true, MiniMapMailBorder = true, MiniMapBattlefieldFrame = true,
        MiniMapLFGFrame = true, GameTimeFrame = true, TimeManagerClockButton = true,
        MiniMapVoiceChatFrame = true, MinimapBackdrop = true, MiniMapInstanceDifficulty = true,
        MinimapZoneTextButton = true, MinimapNorthTag = true, HKSuiteAddonButton = true,
    }

    local function CollectButtons()
        for _, child in ipairs({ Minimap:GetChildren() }) do
            local name = child:GetName()
            if name and not IGNORE[name] and child.IsObjectType and child:IsObjectType("Button")
                and not collectedSet[child] then
                collectedSet[child] = true
                table.insert(collected, child)
            end
        end
    end

    local function LayoutMenu()
        CollectButtons()
        local cols, size, pad = 4, 33, 8
        local n = 0
        for _, b in ipairs(collected) do
            if b:GetParent() ~= menu then b:SetParent(menu) end
            b:ClearAllPoints()
            local col, row = n % cols, math.floor(n / cols)
            b:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + col * size, -(pad + row * size))
            b:SetFrameStrata("DIALOG")
            b:Show()
            n = n + 1
        end
        local rows = math.max(1, math.ceil(n / cols))
        menu:SetWidth(pad * 2 + math.min(n > 0 and n or 1, cols) * size)
        menu:SetHeight(pad * 2 + rows * size)
        menu.empty:SetShown(n == 0)
    end

    local function AnchorMenu()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)   -- flyout from the button
    end

    local function ToggleMenu()
        if not ns.IsModuleEnabled("addonbutton") then return end
        if menu:IsShown() then
            menu:Hide()
        else
            LayoutMenu()
            AnchorMenu()
            menu:Show()
        end
    end

    local function BACKDROP()
        return {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        }
    end

    local function RestoreButtonPos()
        button:ClearAllPoints()
        if type(cfg.buttonPos) == "table" then
            button:SetPoint(cfg.buttonPos[1], UIParent, cfg.buttonPos[2], cfg.buttonPos[3], cfg.buttonPos[4])
        else
            button:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)   -- default: minimap corner
        end
    end

    local function CreateWidgets()
        -- Flyout menu (anchored to the left of the minimap).
        menu = CreateFrame("Frame", "HKSuiteAddonMenu", UIParent)
        menu:SetBackdrop(BACKDROP())
        menu:SetBackdropColor(0, 0, 0, 0.9)
        menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        menu:SetFrameStrata("DIALOG")   -- position set dynamically in AnchorMenu
        menu:SetClampedToScreen(true)
        menu:Hide()
        menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        menu.empty:SetPoint("CENTER")
        menu.empty:SetText("No addon buttons found")
        menu.empty:Hide()

        -- Movable HK button.
        button = CreateFrame("Button", "HKSuiteAddonButton", UIParent)
        button:SetSize(24, 24)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",   -- solid 1px border
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        button:SetBackdropColor(0, 0, 0, 0.85)
        button:SetBackdropBorderColor(0, 0, 0, 1)         -- black border
        button:SetFrameStrata("MEDIUM")
        button:SetClampedToScreen(true)
        button:SetMovable(true)
        button:RegisterForDrag("LeftButton")
        button:RegisterForClicks("LeftButtonUp")

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("HK")
        label:SetTextColor(0.12, 1, 0.12)

        button:SetScript("OnDragStart", function(self)
            if IsControlKeyDown() then self:StartMoving() end
        end)
        button:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            cfg.buttonPos = { point, relPoint, x, y }
        end)
        button:SetScript("OnClick", function()
            if IsControlKeyDown() then return end   -- CTRL is reserved for dragging
            if IsShiftKeyDown() then
                InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)
                InterfaceOptionsFrame_OpenToCategory(ns.overviewPanel)  -- twice: WotLK quirk
                return
            end
            ToggleMenu()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("HKSuite")
            GameTooltip:AddLine("Click: addon buttons menu", 1, 1, 1)
            GameTooltip:AddLine("Shift+click: HKSuite options", 1, 1, 1)
            GameTooltip:AddLine("CTRL+drag: move this button", 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)

        RestoreButtonPos()
    end

    local function ApplyButton()
        button:SetShown(cfg.showButton and ns.IsModuleEnabled("addonbutton"))
    end

    local function BuildOptionsPanel()
        local panel = CreateFrame("Frame")
        panel.name = "Addon Button"
        panel.parent = "HKSuite"

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Addon Button")

        local sb = ns.CreateCheck(panel, "Show the movable HK button",
            "Displays a square HK button (CTRL+drag to move) that opens the addon-buttons menu.", cfg.showButton)
        sb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        sb:SetScript("OnClick", function(self)
            cfg.showButton = self:GetChecked() and true or false
            ApplyButton()
        end)

        local rescan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        rescan:SetSize(160, 24)
        rescan:SetText("Rescan / reset position")
        rescan:SetPoint("TOPLEFT", sb, "BOTTOMLEFT", 0, -16)
        rescan:SetScript("OnClick", function()
            cfg.buttonPos = false
            RestoreButtonPos()
            LayoutMenu()
        end)

        InterfaceOptions_AddCategory(panel)
    end

    function M:OnInit()
        cfg = ns.config.addonbutton
        CreateWidgets()
        ApplyButton()
        BuildOptionsPanel()

        -- Grab minimap buttons on load. Two delayed passes catch addons that
        -- create their button late.
        local function grab()
            if ns.IsModuleEnabled("addonbutton") and cfg.showButton then LayoutMenu() end
        end
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:SetScript("OnEvent", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(2, grab)
                C_Timer.After(5, grab)
            else
                grab()
            end
        end)
    end
end
