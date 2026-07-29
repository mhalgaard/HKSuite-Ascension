local ADDON, ns = ...

-- =============================================================================
-- Chat Filters module: suppress Ascension broadcast spam, channel spam, and
-- say/yell in cities; optionally remove channels from the default chat tab.
-- Ported/reorganised from XanAscTweaks.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "chatfilter",
    title = "Chat Filters",
    desc  = "Hide Ascension broadcast/channel spam and say/yell in cities.",
})

-- System-message (CHAT_MSG_SYSTEM) filters: key -> Lua patterns to suppress.
local SYSTEM_FILTERS = {
    { key = "trial",         label = "Trial / Nightmare broadcasts",
      patterns = { "Htrial:%d-:", "%[.-Resolute.-Mode.-%]", "%[.-Nightmare.-%]" } },
    { key = "mysticAltar",   label = "Mystic Enchanting Altars",
      patterns = { "Hitem:1179126" } },
    { key = "autobroadcast", label = "Ascension autobroadcasts",
      patterns = { "%[.-Ascension.-Autobroadcast.-%]" } },
    { key = "travelGuide",   label = "Travel Guides",
      patterns = { "%[.-Travel Guide.-%]" } },
    { key = "keeperScroll",  label = "Keeper's Scrolls",
      patterns = { "%[.-Keeper'?s.-Scroll.-%]" } },
    { key = "motherlode",    label = "Motherlodes",
      patterns = { "%[.-The.-Motherlode.-%]" } },
    { key = "criminal",      label = "Criminal Intent",
      patterns = { "%[.-Criminal Intent.-%]" } },
    { key = "hardcore",      label = "Hardcore mode",
      patterns = { "%[.-Hardcore.-%]" } },
    { key = "posture",       label = "Posture Check",
      patterns = { "%[.-Posture Check.-%]" } },
    { key = "aleader",       label = "Alliance leader spawns",
      patterns = { "inv_alliancewareffort:16|t.-has spawned" } },
    { key = "hleader",       label = "Horde leader spawns",
      patterns = { "inv_hordewareffort:16|t.-has spawned" } },
    { key = "worldbosses",   label = "World boss spawn alerts",
      patterns = {
          "%[.-Emeriss.-%]", "%[.-Lethon.-%]", "%[.-Ysondre.-%]", "%[.-Taerar.-%]",
          "%[.-Azuregos.-%]", "%[.-Lord Kazzak.-%]", "%[.-Setis.-%]",
          "%[.-The Will of Soggoth.-%]", "%[.-Atal'zul, the Soulreaver.-%]",
          "%[.-Doomwalker.-%]", "%[.-Doom Lord Kazzak.-%]",
      } },
}

-- Public-channel (CHAT_MSG_CHANNEL) spam filters.
local CHANNEL_FILTERS = {
    { key = "bau",     label = "'bau' in chat",         match = function(m) return m:find("bau") end },
    { key = "dp",      label = "'dp' (but not 'dps')",  match = function(m) return not m:find("dps") and m:find("dp") end },
    { key = "twitch",  label = "'twitch' links",        match = function(m) return m:find("twitch") end },
    { key = "discord", label = "'discord.gg' links",    match = function(m) return m:find("discord%.gg") end },
}

local REST_FILTERS = {
    { key = "say",  label = "Hide /say while in a city" },
    { key = "yell", label = "Hide /yell while in a city" },
}

local REMOVE_CHANNELS = {
    { key = "removeNewcomers", label = "Remove Newcomers from the default tab", channel = "Newcomers" },
    { key = "removeAscension", label = "Remove Ascension from the default tab", channel = "Ascension" },
    { key = "removeWorld",     label = "Remove World from the default tab",     channel = "World" },
}

-- Build default config (everything off) and a flat key list for bulk toggles.
local ALL_KEYS = {}
local defaults = {}
local function collect(list)
    for _, f in ipairs(list) do defaults[f.key] = false; ALL_KEYS[#ALL_KEYS + 1] = f.key end
end
collect(SYSTEM_FILTERS); collect(CHANNEL_FILTERS); collect(REST_FILTERS); collect(REMOVE_CHANNELS)
ns.defaults.chatfilter = defaults

local cfg  -- filled in OnInit

-- --------------------------------------------------------------- filters
local function enabled() return ns.IsModuleEnabled("chatfilter") end

local function FilterSystem(_, _, msg)
    if not (enabled() and msg) then return false end
    for _, f in ipairs(SYSTEM_FILTERS) do
        if cfg[f.key] then
            for _, pat in ipairs(f.patterns) do
                if msg:find(pat) then return true end
            end
        end
    end
    return false
end

local function FilterSayYell(_, event, msg)
    if not enabled() then return false end
    if IsResting() then
        if cfg.say and event == "CHAT_MSG_SAY" then return true end
        if cfg.yell and event == "CHAT_MSG_YELL" then return true end
    end
    return false
end

local function FilterEmote(_, _, msg)
    if not (enabled() and msg) then return false end
    return cfg.mysticAltar and msg:find("Use it to empower.-powerful enchants") and true or false
end

local DONT_PARSE = { guild = true, officer = true, raid = true, whisper = true }
local function FilterChannel(_, _, msg, ...)
    if not (enabled() and msg) then return false end
    local channel = select(8, ...)
    if channel then channel = channel:lower() end
    if channel and DONT_PARSE[channel] then return false end
    local m = msg:lower()
    for _, f in ipairs(CHANNEL_FILTERS) do
        if cfg[f.key] and f.match(m) then return true end
    end
    return false
end

local function RemoveChannels()
    if not enabled() then return end
    for _, f in ipairs(REMOVE_CHANNELS) do
        if cfg[f.key] then ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, f.channel) end
    end
end

-- --------------------------------------------------------------- options UI
function M:BuildSettings(page)
    local checks = {}

    local function Add(f, onChange)
        checks[#checks + 1] = page:Check({
            label = f.label,
            get = function() return cfg[f.key] end,
            set = function(v) cfg[f.key] = v end,
            onChange = onChange,
        })
    end

    local function RefreshChecks()
        for _, cb in ipairs(checks) do cb:Refresh() end
    end

    page:Row({
        { text = "All on", width = 100, onClick = function()
            for _, k in ipairs(ALL_KEYS) do cfg[k] = true end
            RefreshChecks()
            RemoveChannels()
        end },
        { text = "All off", width = 100, onClick = function()
            for _, k in ipairs(ALL_KEYS) do cfg[k] = false end
            RefreshChecks()
        end },
    })

    page:Header("Rest areas")
    for _, f in ipairs(REST_FILTERS) do Add(f) end

    page:Header("System broadcasts")
    for _, f in ipairs(SYSTEM_FILTERS) do Add(f) end

    page:Header("Channel spam")
    for _, f in ipairs(CHANNEL_FILTERS) do Add(f) end

    page:Header("Default chat tab")
    for _, f in ipairs(REMOVE_CHANNELS) do Add(f, RemoveChannels) end
    page:Hint("Leaving a channel takes effect straight away; re-joining one needs a reload "
        .. "(or the client will re-add it at the next login).")
end

function M:OnInit()
    cfg = ns.GetConfig("chatfilter")

    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterSystem)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", FilterSayYell)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", FilterSayYell)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_EMOTE", FilterEmote)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", FilterChannel)

    -- Remove channels shortly after login (Ascension re-adds them).
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        if C_Timer and C_Timer.After then C_Timer.After(1, RemoveChannels) else RemoveChannels() end
    end)
end
