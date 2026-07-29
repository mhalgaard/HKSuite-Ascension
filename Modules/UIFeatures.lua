local ADDON, ns = ...

-- =============================================================================
-- UI Features module: small on-screen combat helpers.
--   * In-range tracker  â€” a crosshair over the character, white when the target
--     is in melee range, red when it's out of range.
--   * Trinket tracker   â€” a movable box showing your equipped trinkets and their
--     cooldowns (move with Ctrl + left-drag).
--   * Loot rolls        â€” a "Loot Rolls" section in the objectives tracker
--     listing recently rolled items, expandable to each player's choice.
-- =============================================================================

local M = ns.RegisterModule({
    key   = "uifeatures",
    title = "UI Features",
    desc  = "In-range crosshair, trinket cooldown tracker, and a loot rolls list on the objectives frame.",
})

ns.defaults.uifeatures = {
    rangeTracker   = false,
    rangeSpell     = "",       -- optional: exact ability name to range-check with
    trinketTracker = false,
    trinketPos     = { "CENTER", "CENTER", 0, -160 },  -- point, relPoint, x, y

    lootRolls          = false,
    lootRollsMax       = 4,     -- how many recent items the section lists
    lootRollsHideAfter = 120,   -- hide the section this long after the last roll ended (0 = never)
    lootRollsShowPass  = true,  -- list players who passed
    lootRollsAttach    = true,  -- sit in the objectives tracker (else a free-floating box)
    lootRollsCollapsed = false, -- section collapsed to just its header
    lootRollsPos       = { "TOPRIGHT", "TOPRIGHT", -220, -260 },
}

local cfg  -- filled in OnInit

local function enabled() return ns.IsModuleEnabled("uifeatures") end

-- ------------------------------------------------------------ in-range tracker
-- There's no direct "is target in melee range" API, but IsSpellInRange() is
-- exact for a given ability. Ascension is classless, so instead of assuming a
-- class spell we probe a list of real 5-yard melee abilities and use whichever
-- one the player actually knows (the player can also name their own). We only
-- fall back to the loose CheckInteractDistance (~9.9 yd) if none are found.
local MELEE_SPELLS = {
    -- Rogue
    "Sinister Strike", "Backstab", "Mutilate", "Hemorrhage", "Ghostly Strike", "Gouge", "Eviscerate",
    -- Warrior
    "Rend", "Hamstring", "Mortal Strike", "Bloodthirst", "Overpower", "Revenge",
    "Devastate", "Sunder Armor", "Heroic Strike", "Shield Slam", "Concussion Blow", "Pummel",
    -- Paladin
    "Crusader Strike", "Hammer of the Righteous",
    -- Death Knight
    "Plague Strike", "Blood Strike", "Death Strike", "Obliterate", "Scourge Strike",
    "Frost Strike", "Heart Strike", "Rune Strike",
    -- Hunter (melee)
    "Raptor Strike", "Wing Clip", "Mongoose Bite",
    -- Shaman
    "Stormstrike", "Lava Lash",
    -- Druid
    "Maul", "Mangle (Bear)", "Mangle (Cat)", "Shred", "Claw", "Rake", "Ferocious Bite", "Ravage",
}

local cachedSpell    -- last melee ability that resolved as known
local lastCastSpell  -- most recent spell the player cast (for the "use last" button)

-- IsSpellInRange returns 1 (in range), 0 (out of range), or nil (unknown spell /
-- invalid target). With a valid hostile target, a known melee spell returns 0/1,
-- so a non-nil result reliably means "the player has this ability".
local scanFailedAt          -- when a full probe last came up empty
local RESCAN_AFTER = 5      -- seconds before walking the whole list again

local function InvalidateMeleeSpell()
    cachedSpell, scanFailedAt = nil, nil
end

local function ResolveMeleeSpell()
    local custom = cfg.rangeSpell
    if custom and custom ~= "" and IsSpellInRange(custom, "target") ~= nil then
        return custom
    end
    if cachedSpell and IsSpellInRange(cachedSpell, "target") ~= nil then
        return cachedSpell
    end
    -- A full probe is one IsSpellInRange call per entry in MELEE_SPELLS. Ascension
    -- is classless, so plenty of builds know none of them -- and with no memory of
    -- that we walked the whole list ten times a second for as long as a hostile
    -- target was up. Back off after an empty probe; learning a spell clears it.
    if scanFailedAt and (GetTime() - scanFailedAt) < RESCAN_AFTER then
        return nil
    end
    for _, name in ipairs(MELEE_SPELLS) do
        if IsSpellInRange(name, "target") ~= nil then
            cachedSpell, scanFailedAt = name, nil
            return name
        end
    end
    scanFailedAt = GetTime()
    return nil
end

local function TargetInMeleeRange()
    local spell = ResolveMeleeSpell()
    if spell then
        return IsSpellInRange(spell, "target") == 1
    end
    return CheckInteractDistance("target", 3) and true or false
end

local WHITE = { 1, 1, 1 }
local RED   = { 1, 0.15, 0.15 }

local crossFrame
local function BuildCross()
    crossFrame = CreateFrame("Frame", "HKSuiteRangeCross", UIParent)
    crossFrame:SetSize(24, 24)
    crossFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    crossFrame:SetFrameStrata("MEDIUM")

    local hbar = crossFrame:CreateTexture(nil, "OVERLAY")
    hbar:SetTexture("Interface\\Buttons\\WHITE8X8")
    hbar:SetSize(22, 2)
    hbar:SetPoint("CENTER")

    local vbar = crossFrame:CreateTexture(nil, "OVERLAY")
    vbar:SetTexture("Interface\\Buttons\\WHITE8X8")
    vbar:SetSize(2, 22)
    vbar:SetPoint("CENTER")

    crossFrame.bars = { hbar, vbar }

    -- The frame must stay shown or its OnUpdate never fires; we toggle the bars.
    -- Only act on an actual change: the tracker spends most of its life disabled
    -- or without a target, and re-hiding already-hidden textures ten times a
    -- second is pure waste.
    local barsShown
    local function ShowBars(show)
        show = show and true or false
        if barsShown == show then return end
        barsShown = show
        for _, bar in ipairs(crossFrame.bars) do
            if show then bar:Show() else bar:Hide() end
        end
    end
    ShowBars(false)

    crossFrame:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.1 then return end
        self.elapsed = 0

        if not (enabled() and cfg.rangeTracker) then
            ShowBars(false)
            return
        end
        -- Only meaningful with a live, attackable target.
        if not UnitExists("target") or UnitIsDead("target")
            or not UnitCanAttack("player", "target") then
            ShowBars(false)
            return
        end

        ShowBars(true)
        local c = TargetInMeleeRange() and WHITE or RED
        for _, bar in ipairs(self.bars) do
            bar:SetVertexColor(c[1], c[2], c[3])
        end
    end)
end

-- ------------------------------------------------------------ trinket tracker
local SLOTS = { 13, 14 }   -- INVSLOT_TRINKET1 / INVSLOT_TRINKET2
local ICON = 36
local PAD, GAP = 4, 1

local trinketBox, icons

local function FormatTime(r)
    if r >= 60 then return math.floor(r / 60) .. "m" end
    return tostring(math.ceil(r))
end

local function UpdateTrinkets()
    if not trinketBox then return end
    if not (enabled() and cfg.trinketTracker) then
        trinketBox:Hide()
        return
    end
    trinketBox:Show()
    for i, slot in ipairs(SLOTS) do
        local icon = icons[i]
        local tex = GetInventoryItemTexture("player", slot)
        if tex then
            icon.texture:SetTexture(tex)
            icon.texture:Show()
            local start, duration, enable = GetInventoryItemCooldown("player", slot)
            if enable == 1 and duration and duration > 0 and start > 0 then
                icon.cd:SetCooldown(start, duration)
            else
                icon.cd:SetCooldown(0, 0)
                icon.text:SetText("")
            end
        else
            icon.texture:Hide()      -- empty slot: keep the frame (so the box stays draggable)
            icon.cd:SetCooldown(0, 0)
            icon.text:SetText("")
        end
    end
end

local function SavePosition()
    local point, _, relPoint, x, y = trinketBox:GetPoint()
    cfg.trinketPos = { point, relPoint, x, y }
end

local function BuildTrinketBox()
    local width = PAD * 2 + ICON * #SLOTS + GAP * (#SLOTS - 1)
    trinketBox = CreateFrame("Frame", "HKSuiteTrinketTracker", UIParent)
    trinketBox:SetSize(width, PAD * 2 + ICON)
    local p = cfg.trinketPos
    trinketBox:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or -160)
    trinketBox:SetFrameStrata("BACKGROUND")
    trinketBox:SetClampedToScreen(true)
    trinketBox:SetMovable(true)
    trinketBox:EnableMouse(true)
    trinketBox:RegisterForDrag("LeftButton")
    trinketBox:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() then self:StartMoving() end
    end)
    trinketBox:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    icons = {}
    for i = 1, #SLOTS do
        local holder = CreateFrame("Frame", nil, trinketBox)
        holder:SetSize(ICON, ICON)
        holder:SetPoint("LEFT", trinketBox, "LEFT", PAD + (i - 1) * (ICON + GAP), 0)
        holder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        holder:SetBackdropColor(0, 0, 0, 0.6)
        -- No mouse on the icons, so drags land on the parent box.

        local texture = holder:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", 2, -2)
        texture:SetPoint("BOTTOMRIGHT", -2, 2)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default icon border
        holder.texture = texture

        local cd = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
        cd:SetAllPoints(texture)
        holder.cd = cd

        local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("BOTTOM", 0, 2)
        holder.text = text

        icons[i] = holder
    end

    -- Numeric cooldown countdown (the sweep alone has no number in 3.3.5).
    trinketBox:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.1 then return end
        self.elapsed = 0
        for i, slot in ipairs(SLOTS) do
            local icon = icons[i]
            if icon.texture:IsShown() then
                local start, duration, enable = GetInventoryItemCooldown("player", slot)
                if enable == 1 and duration and duration > 0 and start > 0 then
                    local r = start + duration - GetTime()
                    icon.text:SetText(r > 0 and FormatTime(r) or "")
                else
                    icon.text:SetText("")
                end
            end
        end
    end)

    trinketBox:Hide()
end

-- --------------------------------------------------------------- loot rolls
-- A "Loot Rolls" section for the objectives tracker.
--
-- Group loot in 3.3.5 exposes the *item* being rolled (GetLootRollItemInfo) but
-- nothing about who has answered. The only source for that is the chat traffic
-- the server broadcasts to the group ("X has selected Need for: [item]"), so we
-- parse CHAT_MSG_LOOT. The patterns are built from the client's own GlobalStrings
-- rather than hardcoded English, and each capture is identified by its content
-- (item link / number / name) so the argument order in a translation can't break
-- them.
--
-- "Who is missing" is the group roster snapshotted when the roll started, minus
-- everyone who has answered. Players who cannot loot the item auto-pass, so they
-- resolve on their own; players out of the loot group simply never answer and
-- stay listed as waiting until the roll times out.

local LR_HEADER_H, LR_ITEM_H, LR_PLAYER_H = 16, 15, 12
local LR_PAD, LR_DEFAULT_W = 3, 204
local LR_ITEM_INDENT, LR_PLAYER_INDENT = 25, 32   -- item names clear the icon; players nest under them

-- Roll choices, in the order group loot numbers them.
local VOTE = {
    [0] = { short = "Pass",  color = { 0.55, 0.55, 0.55 } },
    [1] = { short = "Need",  color = { 0.30, 1.00, 0.35 } },
    [2] = { short = "Greed", color = { 1.00, 0.82, 0.10 } },
    [3] = { short = "DE",    color = { 0.72, 0.45, 1.00 } },
}
local WAITING_COLOR = { 1.00, 0.55, 0.15 }
local DIM_COLOR     = { 0.45, 0.45, 0.45 }

local rolls    = {}   -- roll records, newest first
local rollByID = {}   -- live rollID -> record
local lootFrame, lrRows, lrHeader
local trackerCollapsed = false
local baseWatchOffset, pushedHeight

local RefreshLootRolls   -- forward declaration (event handlers call it)

-- Turn a GlobalStrings format ("%s has selected Need for: %s") into a Lua
-- pattern. Placeholders go in as control bytes first so the (%d+) we inject for
-- a number can't be re-matched by the later %d pass.
local function BuildPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%%d%%%$s", "\1")     -- positional "%1$s"
    p = p:gsub("%%%d%%%$d", "\2")     -- positional "%1$d"
    p = p:gsub("%%s", "\1")
    p = p:gsub("%%d", "\2")
    p = p:gsub("\1", "(.+)")
    p = p:gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- Sort a pattern's captures by what they contain, not by position.
local function ParseCaps(...)
    local player, link, num
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then
            if v:find("|H", 1, true) then link = v
            elseif v:match("^%d+$") then num = tonumber(v)
            else player = v end
        end
    end
    return player, link, num
end

-- Message kinds we care about, most specific first: the auto-pass lines have to
-- be tested before the plain "passed on" line, which would otherwise swallow
-- them. `en` is only a fallback for a client missing the global.
local LOOT_MESSAGES = {
    { g = "LOOT_ROLL_PASSED_SELF_AUTO", en = "You automatically passed on: %s because you cannot loot that item.", vote = 0, me = true },
    { g = "LOOT_ROLL_PASSED_AUTO",        en = "%s automatically passed on: %s because he cannot loot that item.",  vote = 0 },
    { g = "LOOT_ROLL_PASSED_AUTO_FEMALE", en = "%s automatically passed on: %s because she cannot loot that item.", vote = 0 },
    { g = "LOOT_ROLL_PASSED_SELF",     en = "You passed on: %s",                     vote = 0, me = true },
    { g = "LOOT_ROLL_PASSED",          en = "%s passed on: %s",                      vote = 0 },
    { g = "LOOT_ROLL_NEED_SELF",       en = "You have selected Need for: %s",        vote = 1, me = true },
    { g = "LOOT_ROLL_NEED",            en = "%s has selected Need for: %s",          vote = 1 },
    { g = "LOOT_ROLL_GREED_SELF",      en = "You have selected Greed for: %s",       vote = 2, me = true },
    { g = "LOOT_ROLL_GREED",           en = "%s has selected Greed for: %s",         vote = 2 },
    { g = "LOOT_ROLL_DISENCHANT_SELF", en = "You have selected Disenchant for: %s",  vote = 3, me = true },
    { g = "LOOT_ROLL_DISENCHANT",      en = "%s has selected Disenchant for: %s",    vote = 3 },
    -- The rolled numbers arrive once the roll closes. No English fallback: the
    -- wording varies between builds and the section reads fine without them.
    { g = "LOOT_ROLL_ROLLED_NEED", vote = 1, rolled = true },
    { g = "LOOT_ROLL_ROLLED_GREED", vote = 2, rolled = true },
    { g = "LOOT_ROLL_ROLLED_DE",   vote = 3, rolled = true },
    { g = "LOOT_ROLL_ALL_PASSED",  allPassed = true },
    -- Who actually walked away with it.
    { g = "LOOT_ITEM_SELF_MULTIPLE", won = true, me = true },
    { g = "LOOT_ITEM_SELF",          won = true, me = true },
    { g = "LOOT_ITEM_MULTIPLE",      won = true },
    { g = "LOOT_ITEM",               won = true },
}

local function CompileLootPatterns()
    for _, m in ipairs(LOOT_MESSAGES) do
        m.pattern = BuildPattern(_G[m.g] or m.en)
    end
end

-- ---------------------------------------------------------------- group data
local function RaidSize()  return (GetNumRaidMembers  and GetNumRaidMembers()  or 0) end
local function PartySize() return (GetNumPartyMembers and GetNumPartyMembers() or 0) end

local function GroupRoster()
    local names, classes = {}, {}
    local function add(unit)
        local n = UnitName(unit)
        if n and n ~= UNKNOWNOBJECT then
            names[#names + 1] = n
            classes[n] = select(2, UnitClass(unit))
        end
    end
    local raid = RaidSize()
    if raid > 0 then
        for i = 1, raid do add("raid" .. i) end
    else
        add("player")
        for i = 1, PartySize() do add("party" .. i) end
    end
    return names, classes
end

local function LookupClass(name)
    local raid = RaidSize()
    if raid > 0 then
        for i = 1, raid do
            if UnitName("raid" .. i) == name then return select(2, UnitClass("raid" .. i)) end
        end
    else
        if UnitName("player") == name then return select(2, UnitClass("player")) end
        for i = 1, PartySize() do
            if UnitName("party" .. i) == name then return select(2, UnitClass("party" .. i)) end
        end
    end
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- ------------------------------------------------------------- roll records
local function ItemKey(link)
    return link and link:match("item:(%d+)")
end

-- Locate the roll a chat line refers to. Prefers a still-open roll the player
-- hasn't answered yet, so two simultaneous rolls of the same item fill in turn.
local function FindRoll(link, playerName, anyState)
    if not link then return end
    local key, name = ItemKey(link), link:match("%[(.-)%]")
    local fallback
    for _, r in ipairs(rolls) do
        if (key and r.key == key) or (name and r.name == name) then
            if not anyState and not r.finished
                and (playerName == nil or r.votes[playerName] == nil) then
                return r
            end
            fallback = fallback or r
        end
    end
    return fallback
end

local function Responded(rec)
    local n = 0
    for _ in pairs(rec.votes) do n = n + 1 end
    return n
end

local function Finish(rec)
    if not rec.finished then
        rec.finished = GetTime()
        if rec.rollID then rollByID[rec.rollID] = nil end
    end
end

local function CheckComplete(rec)
    for _, name in ipairs(rec.candidates) do
        if rec.votes[name] == nil then return end
    end
    Finish(rec)
end

-- Group loot awards to the highest Need roll if there is one, else the highest
-- Greed/Disenchant roll -- so that's how we pick the winner from the numbers.
local function Winner(rec)
    if rec.wonBy then return rec.wonBy, rec.rollNums[rec.wonBy] end
    local bestName, bestNum, bestNeed
    for name, num in pairs(rec.rollNums) do
        local need = (rec.votes[name] == 1)
        if bestName == nil or (need and not bestNeed)
            or (need == bestNeed and num > bestNum) then
            bestName, bestNum, bestNeed = name, num, need
        end
    end
    return bestName, bestNum
end

local function TrimRolls()
    local keep = math.max(1, tonumber(cfg.lootRollsMax) or 4) * 3
    for i = #rolls, keep + 1, -1 do
        local rec = rolls[i]
        if rec.rollID then rollByID[rec.rollID] = nil end
        table.remove(rolls, i)
    end
end

local function StartRoll(rollID, rollTime)
    local texture, name, count, quality, bop = GetLootRollItemInfo(rollID)
    if not name then return end
    local link = GetLootRollItemLink(rollID)
    local names, classes = GroupRoster()
    local rec = {
        rollID = rollID, link = link, name = name, texture = texture,
        count = count or 1, quality = quality or 1, bop = bop,
        key = ItemKey(link),
        started = GetTime(),
        deadline = GetTime() + ((tonumber(rollTime) or 60000) / 1000),
        candidates = names, classes = classes,
        votes = {}, order = {}, rollNums = {},
    }
    table.insert(rolls, 1, rec)
    rollByID[rollID] = rec
    TrimRolls()
    RefreshLootRolls()
end

-- Character names never contain a space, so a captured "name" that does means we
-- matched a broader message than we meant to (e.g. an auto-pass line falling
-- through to the plain "passed on" pattern). Drop it rather than invent a player.
local function ValidName(name)
    return name and name ~= "" and not name:find("%s")
end

local function RecordVote(link, playerName, vote)
    if not ValidName(playerName) then return end
    local rec = FindRoll(link, playerName)
    if not rec then return end
    if rec.votes[playerName] == nil then
        rec.order[#rec.order + 1] = playerName
        local known
        for _, n in ipairs(rec.candidates) do
            if n == playerName then known = true break end
        end
        if not known then rec.candidates[#rec.candidates + 1] = playerName end
        rec.classes[playerName] = rec.classes[playerName] or LookupClass(playerName)
    end
    rec.votes[playerName] = vote
    CheckComplete(rec)
    RefreshLootRolls()
end

local function RecordRolled(link, playerName, num, vote)
    if not (ValidName(playerName) and num) then return end
    local rec = FindRoll(link, nil, true)
    if not rec then return end
    if rec.votes[playerName] == nil then RecordVote(link, playerName, vote) end
    rec.rollNums[playerName] = num
    Finish(rec)
    RefreshLootRolls()
end

local function RecordWinner(link, playerName)
    local rec = FindRoll(link, nil, true)
    -- Only a roll that just closed; otherwise ordinary looting of the same item
    -- id later on would rewrite the result.
    if not rec or not rec.finished or rec.wonBy then return end
    if GetTime() - rec.finished > 20 then return end
    rec.wonBy = playerName
    RefreshLootRolls()
end

local function HandleLootMessage(msg)
    if not msg then return end
    for _, m in ipairs(LOOT_MESSAGES) do
        if m.pattern then
            local a, b, c = msg:match(m.pattern)
            if a then
                local player, link, num = ParseCaps(a, b, c)
                if m.me then player = UnitName("player") end
                if m.allPassed then
                    local rec = FindRoll(link, nil, true)
                    if rec then rec.allPassed = true; Finish(rec); RefreshLootRolls() end
                elseif m.won then
                    RecordWinner(link, player)
                elseif m.rolled then
                    RecordRolled(link, player, num, m.vote)
                elseif player then
                    RecordVote(link, player, m.vote)
                end
                return
            end
        end
    end
end

-- ------------------------------------------------------------------ display
-- Pending rolls open themselves so you can see who is still missing; once
-- nothing is pending, the roll that finished most recently opens instead.
local function IsExpanded(rec, newestFinished, anyPending)
    if rec.userExpanded ~= nil then return rec.userExpanded end
    if not rec.finished then return true end
    return (not anyPending) and rec == newestFinished
end

-- FontStrings in 3.3.5 wrap instead of eliding, so trim to fit by hand.
local function SetTruncated(fs, text, maxWidth)
    fs:SetText(text or "")
    if not maxWidth or maxWidth <= 0 then return end
    local s = text or ""
    while #s > 1 and fs:GetStringWidth() > maxWidth do
        s = s:sub(1, #s - 1)
        fs:SetText(s .. "...")
    end
end

local function RowOnEnter(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
end

local function RowOnLeave() GameTooltip:Hide() end

local function RowOnClick(self)
    local rec = self.rec
    if not rec then return end
    if IsShiftKeyDown() and rec.link and ChatEdit_InsertLink then
        ChatEdit_InsertLink(rec.link)
    elseif IsControlKeyDown() and rec.link and DressUpItemLink then
        DressUpItemLink(rec.link)
    else
        rec.userExpanded = not self.expanded
        RefreshLootRolls()
    end
end

local function GetRow(i)
    local row = lrRows[i]
    if row then return row end

    row = CreateFrame("Button", nil, lootFrame)
    row:SetPoint("LEFT", lootFrame, "LEFT", 0, 0)
    row:SetPoint("RIGHT", lootFrame, "RIGHT", 0, 0)

    row.toggle = row:CreateTexture(nil, "ARTWORK")
    row.toggle:SetSize(10, 10)
    row.toggle:SetPoint("LEFT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(11, 11)
    row.icon:SetPoint("LEFT", 12, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.left:SetPoint("LEFT", 25, 0)
    row.left:SetJustifyH("LEFT")

    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetJustifyH("RIGHT")

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:GetHighlightTexture():SetAlpha(0.35)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)

    lrRows[i] = row
    return row
end

local function LayoutItemRow(row, rec, y, width, expanded)
    row:SetHeight(LR_ITEM_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", lootFrame, "TOPRIGHT", 0, y)
    row.rec, row.link, row.expanded = rec, rec.link, expanded
    row:EnableMouse(true)

    row.toggle:SetTexture(expanded and "Interface\\Buttons\\UI-MinusButton-Up"
                                    or "Interface\\Buttons\\UI-PlusButton-Up")
    row.toggle:Show()
    row.icon:SetTexture(rec.texture)
    row.icon:Show()

    -- Right column: progress + countdown while open, the outcome once closed.
    local rightText, rc, rg, rb
    if rec.finished then
        if rec.allPassed then
            rightText = "all passed"
            rc, rg, rb = unpack(DIM_COLOR)
        else
            local win, num = Winner(rec)
            if win then
                rightText = num and (win .. " " .. num) or win
                rc, rg, rb = ClassColor(rec.classes[win] or LookupClass(win))
            else
                rightText = "done"
                rc, rg, rb = unpack(DIM_COLOR)
            end
        end
    else
        local left = math.max(0, math.ceil(rec.deadline - GetTime()))
        rightText = Responded(rec) .. "/" .. #rec.candidates .. "  " .. left .. "s"
        rc, rg, rb = unpack(WAITING_COLOR)
    end
    row.right:SetText(rightText)
    row.right:SetTextColor(rc, rg, rb)

    local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rec.quality]
    row.left:SetTextColor(q and q.r or 1, q and q.g or 1, q and q.b or 1)
    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row, "LEFT", LR_ITEM_INDENT, 0)
    local label = rec.count > 1 and (rec.count .. "x " .. rec.name) or rec.name
    SetTruncated(row.left, label, width - LR_ITEM_INDENT - row.right:GetStringWidth() - 6)
end

local function LayoutPlayerRow(row, rec, name, y, width)
    row:SetHeight(LR_PLAYER_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", lootFrame, "TOPRIGHT", 0, y)
    row.rec, row.link, row.expanded = nil, nil, nil
    row:EnableMouse(false)
    row.toggle:Hide()
    row.icon:Hide()

    local vote = rec.votes[name]
    local rightText, rc, rg, rb
    if vote then
        local v = VOTE[vote]
        local num = rec.rollNums[name]
        rightText = num and (v.short .. " " .. num) or v.short
        rc, rg, rb = unpack(v.color)
    else
        rightText = "waiting"
        rc, rg, rb = unpack(WAITING_COLOR)
    end
    row.right:SetText(rightText)
    row.right:SetTextColor(rc, rg, rb)

    if vote then
        row.left:SetTextColor(ClassColor(rec.classes[name]))
    else
        row.left:SetTextColor(unpack(DIM_COLOR))
    end
    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row, "LEFT", LR_PLAYER_INDENT, 0)
    SetTruncated(row.left, name, width - LR_PLAYER_INDENT - row.right:GetStringWidth() - 6)
end

-- Answered first (in the order they answered), then everyone still missing.
local function PlayerOrder(rec)
    local list, seen = {}, {}
    for _, name in ipairs(rec.order) do
        if not seen[name] then
            seen[name] = true
            if cfg.lootRollsShowPass or rec.votes[name] ~= 0 then list[#list + 1] = name end
        end
    end
    for _, name in ipairs(rec.candidates) do
        if not seen[name] and rec.votes[name] == nil then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    return list
end

local function VisibleRolls()
    local max = math.max(1, tonumber(cfg.lootRollsMax) or 4)
    local list = {}
    for i = 1, math.min(#rolls, max) do list[i] = rolls[i] end
    return list
end

local function ShouldShow()
    if not (enabled() and cfg.lootRolls) then return false end
    if trackerCollapsed and cfg.lootRollsAttach then return false end
    if #rolls == 0 then return false end
    local hideAfter = tonumber(cfg.lootRollsHideAfter) or 0
    if hideAfter > 0 then
        local newest = rolls[1]
        if newest.finished and (GetTime() - newest.finished) > hideAfter then return false end
    end
    return true
end

-- Reserve room at the top of the tracker so the quest lines start below us.
-- WatchFrame_Update reads WATCHFRAME_INITIAL_OFFSET each time it lays out, so
-- shifting the global and asking for a relayout is all it takes. We stay out of
-- combat when forcing that relayout: the tracker's quest-item buttons are
-- protected, and poking Blizzard's layout mid-fight risks blocking them.
local function PushTracker(height)
    if type(baseWatchOffset) ~= "number" then return end
    if pushedHeight == height then return end
    pushedHeight = height
    WATCHFRAME_INITIAL_OFFSET = baseWatchOffset - height
    if type(WatchFrame_Update) == "function" and not InCombatLockdown() then
        WatchFrame_Update()
    end
end

local function ApplyPlacement()
    if not lootFrame then return end
    local wf = _G.WatchFrame
    lootFrame:ClearAllPoints()
    if cfg.lootRollsAttach and wf then
        local w = wf:GetWidth()
        if not w or w < 60 then w = LR_DEFAULT_W end
        lootFrame:SetWidth(w)
        if baseWatchOffset then
            -- Room was reserved at the top of the tracker: sit in it.
            lootFrame:SetPoint("TOPLEFT", wf, "TOPLEFT", 0, 0)
        else
            -- No offset to claim on this client, so stack above the tracker
            -- instead of drawing over the first quest.
            lootFrame:SetPoint("BOTTOMLEFT", wf, "TOPLEFT", 0, 4)
        end
        lootFrame:SetFrameStrata(wf:GetFrameStrata())
        lootFrame:SetFrameLevel(wf:GetFrameLevel() + 5)
        lootFrame:EnableMouse(false)
    else
        lootFrame:SetWidth(LR_DEFAULT_W)
        local p = cfg.lootRollsPos or {}
        lootFrame:SetPoint(p[1] or "TOPRIGHT", UIParent, p[2] or "TOPRIGHT", p[3] or -220, p[4] or -260)
        lootFrame:SetFrameStrata("MEDIUM")
        lootFrame:EnableMouse(true)
    end
end

function RefreshLootRolls()
    if not lootFrame then return end

    if not ShouldShow() then
        lootFrame:Hide()
        PushTracker(0)
        return
    end

    ApplyPlacement()
    local width = lootFrame:GetWidth()
    local visible = VisibleRolls()

    -- Header. The tracker's own collapse button sits in the top-right corner, so
    -- keep the header text clear of it.
    local pending = 0
    for _, rec in ipairs(visible) do
        if not rec.finished then pending = pending + 1 end
    end
    lrHeader.text:SetText(pending > 0 and ("Loot Rolls (" .. pending .. ")") or "Loot Rolls")
    lrHeader.toggle:SetTexture(cfg.lootRollsCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                                                       or "Interface\\Buttons\\UI-MinusButton-Up")

    local used, y = 0, -LR_HEADER_H
    if cfg.lootRollsCollapsed then
        for _, row in ipairs(lrRows) do row:Hide() end
    else
        local anyPending, newestFinished = pending > 0, nil
        for _, rec in ipairs(visible) do
            if rec.finished and not newestFinished then newestFinished = rec end
        end

        for _, rec in ipairs(visible) do
            local expanded = IsExpanded(rec, newestFinished, anyPending)
            used = used + 1
            local row = GetRow(used)
            LayoutItemRow(row, rec, y, width, expanded)
            row:Show()
            y = y - LR_ITEM_H

            if expanded then
                for _, name in ipairs(PlayerOrder(rec)) do
                    used = used + 1
                    local prow = GetRow(used)
                    LayoutPlayerRow(prow, rec, name, y, width)
                    prow:Show()
                    y = y - LR_PLAYER_H
                end
            end
        end
        for i = used + 1, #lrRows do lrRows[i]:Hide() end
    end

    local height = LR_HEADER_H + (-y - LR_HEADER_H) + LR_PAD
    lootFrame:SetHeight(math.max(LR_HEADER_H, height))
    lootFrame:Show()
    PushTracker(cfg.lootRollsAttach and (height + 4) or 0)
end

local function SaveLootRollsPosition()
    local point, _, relPoint, x, y = lootFrame:GetPoint()
    cfg.lootRollsPos = { point, relPoint, x, y }
end

local function BuildLootRollsFrame()
    lootFrame = CreateFrame("Frame", "HKSuiteLootRolls", UIParent)
    lootFrame:SetSize(LR_DEFAULT_W, LR_HEADER_H)
    lootFrame:SetMovable(true)
    lootFrame:RegisterForDrag("LeftButton")
    lootFrame:SetScript("OnDragStart", function(self)
        if IsControlKeyDown() and not cfg.lootRollsAttach then self:StartMoving() end
    end)
    lootFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveLootRollsPosition()
    end)
    lootFrame:Hide()

    lrRows = {}

    lrHeader = CreateFrame("Button", nil, lootFrame)
    lrHeader:SetHeight(LR_HEADER_H)
    lrHeader:SetPoint("TOPLEFT", 0, 0)
    lrHeader:SetPoint("TOPRIGHT", -22, 0)   -- clear of the tracker's collapse button
    lrHeader.toggle = lrHeader:CreateTexture(nil, "ARTWORK")
    lrHeader.toggle:SetSize(10, 10)
    lrHeader.toggle:SetPoint("LEFT", 0, 0)
    lrHeader.text = lrHeader:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lrHeader.text:SetPoint("LEFT", 13, 0)
    lrHeader.text:SetTextColor(1, 0.82, 0)
    lrHeader:SetScript("OnClick", function()
        cfg.lootRollsCollapsed = not cfg.lootRollsCollapsed
        RefreshLootRolls()
    end)

    if _G.WatchFrame then
        if type(WATCHFRAME_INITIAL_OFFSET) == "number" then
            baseWatchOffset = WATCHFRAME_INITIAL_OFFSET
        end
        -- The tracker resizes itself (collapse, expanded width); keep in step.
        if type(WatchFrame_Update) == "function" then
            hooksecurefunc("WatchFrame_Update", function()
                if lootFrame:IsShown() then ApplyPlacement() end
            end)
        end
        if type(WatchFrame_Collapse) == "function" then
            hooksecurefunc("WatchFrame_Collapse", function()
                trackerCollapsed = true
                RefreshLootRolls()
            end)
        end
        if type(WatchFrame_Expand) == "function" then
            hooksecurefunc("WatchFrame_Expand", function()
                trackerCollapsed = false
                RefreshLootRolls()
            end)
        end
    end

    -- Drives the countdown, closes rolls nobody answered, and hides the section
    -- once it has gone stale (or the module was switched off in the settings).
    -- Nothing here can matter until a roll has actually been recorded, so the
    -- common case -- feature off, or simply not in a group -- costs one table
    -- length check.
    lootFrame.ticker = CreateFrame("Frame")
    lootFrame.ticker:SetScript("OnUpdate", function(self, e)
        self.elapsed = (self.elapsed or 0) + e
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        if #rolls == 0 then return end

        local now = GetTime()
        local dirty, pending = false, false
        for _, rec in ipairs(rolls) do
            if not rec.finished then
                if now >= rec.deadline then
                    Finish(rec)
                    dirty = true
                else
                    pending = true
                end
            end
        end
        -- The countdown only needs redrawing once a second.
        local sec = math.floor(now)
        if pending and sec ~= self.lastSec then
            self.lastSec = sec
            dirty = true
        end
        -- IsShown() is 1/nil here, so normalise before comparing.
        local shown = lootFrame:IsShown() and true or false
        if dirty or shown ~= ShouldShow() then
            RefreshLootRolls()
        end
    end)
end

-- ------------------------------------------------------------------- options
function M:BuildSettings(page)
    page:Header("In-range tracker")
    page:Check({
        label = "Enable in-range tracker",
        tooltip = "Shows a crosshair over your character: white when your target is in melee range, red when out of range.",
        get = function() return cfg.rangeTracker end,
        set = function(v) cfg.rangeTracker = v end,
    })

    local saved
    local function SavedText()
        local v = cfg.rangeSpell
        if v and v ~= "" then return "Using: |cff00ff00" .. v .. "|r" end
        return "Using: |cffaaaaaa(auto-detected from the melee abilities you know)|r"
    end

    local spell = page:Input({
        label = "Melee ability for the range check (optional)",
        name = "HKSuiteRangeSpellBox", width = 220,
        tooltip = "Ascension is classless, so with this blank the tracker probes a list of real "
            .. "5-yard melee abilities and uses whichever one you actually know.",
        get = function() return cfg.rangeSpell or "" end,
        set = function(v)
            cfg.rangeSpell = v
            InvalidateMeleeSpell()          -- force a re-resolve with the new preference
        end,
        onChange = function() if saved then saved:SetText(SavedText()) end end,
    })

    saved = page:Hint(SavedText())

    -- Setting it from the last ability you cast is the reliable route: the
    -- spellbook can't be open while these settings are, so shift-clicking a spell
    -- into the box usually isn't possible.
    page:Button({
        text = "Set from last-used ability", width = 220,
        tooltip = "Cast your melee ability once, then click this.",
        onClick = function()
            if lastCastSpell and lastCastSpell ~= "" then
                cfg.rangeSpell = lastCastSpell
                InvalidateMeleeSpell()
                spell:Refresh()
                saved:SetText(SavedText())
                ns.Print("Range ability set to: " .. lastCastSpell)
            else
                ns.Print("Cast your melee ability once, then click 'Set from last-used ability'.")
            end
        end,
    })

    -- Now that settings live in their own window the spellbook can be open at the
    -- same time, so shift-clicking a spell into the box finally works.
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and spell.box:HasFocus() then
            cfg.rangeSpell = tostring(link):match("%[(.-)%]") or tostring(link)
            InvalidateMeleeSpell()
            spell:Refresh()
            saved:SetText(SavedText())
        end
    end)

    page:OnRefresh(function() saved:SetText(SavedText()) end)

    page:Header("Trinket tracker")
    page:Check({
        label = "Enable trinket tracker",
        tooltip = "Shows your equipped trinkets and their cooldowns in a box.",
        get = function() return cfg.trinketTracker end,
        set = function(v) cfg.trinketTracker = v end,
        onChange = UpdateTrinkets,
    })
    page:Hint("Hold Ctrl and left-drag the trinket box to reposition it.")

    page:Header("Loot rolls")
    page:Text("Adds a Loot Rolls section to the objectives frame listing the items your group most "
        .. "recently rolled on. Click an item to see every player's choice. Rolls that are still open "
        .. "stay expanded so you can see who has not answered yet; otherwise the roll that finished "
        .. "most recently is the one shown expanded.")

    page:Check({
        label = "Show the loot rolls list",
        tooltip = "Lists recent group loot rolls in the objectives frame.",
        get = function() return cfg.lootRolls end,
        set = function(v) cfg.lootRolls = v end,
        onChange = RefreshLootRolls,
    })

    page:Check({
        label = "Attach to the objectives frame",
        tooltip = "On: the list sits at the top of the quest tracker and pushes your quests down.\n\n"
            .. "Off: the list becomes a free-floating box you can move with Ctrl + left-drag.",
        get = function() return cfg.lootRollsAttach end,
        set = function(v) cfg.lootRollsAttach = v end,
        onChange = function()
            PushTracker(0)          -- give the tracker its space back before re-anchoring
            RefreshLootRolls()
        end,
    })

    page:Check({
        label = "List players who passed",
        tooltip = "When off, players who passed are left out of the expanded list. They still count "
            .. "towards the answered total.",
        get = function() return cfg.lootRollsShowPass end,
        set = function(v) cfg.lootRollsShowPass = v end,
        onChange = RefreshLootRolls,
    })

    page:Input({
        label = "Items to list", width = 80,
        name = "HKSuiteLootRollsMaxBox",
        tooltip = "How many of the most recent items the section shows.",
        numeric = true, min = 1, max = 10, step = 1,
        get = function() return cfg.lootRollsMax end,
        set = function(v) cfg.lootRollsMax = v end,
        onChange = RefreshLootRolls,
    })

    page:Input({
        label = "Hide the list this long after the last roll (seconds, 0 = never)", width = 80,
        name = "HKSuiteLootRollsHideBox",
        tooltip = "The section disappears once the newest roll has been finished for this long.",
        numeric = true, min = 0, max = 3600, step = 1,
        get = function() return cfg.lootRollsHideAfter end,
        set = function(v) cfg.lootRollsHideAfter = v end,
        onChange = RefreshLootRolls,
    })
end

function M:OnInit()
    cfg = ns.GetConfig("uifeatures")

    BuildCross()
    BuildTrinketBox()
    CompileLootPatterns()
    BuildLootRollsFrame()

    -- Loot rolls: START_LOOT_ROLL gives us the item, the chat traffic gives us
    -- the answers, CANCEL_LOOT_ROLL tells us the roll is over.
    local loot = CreateFrame("Frame")
    loot:RegisterEvent("START_LOOT_ROLL")
    loot:RegisterEvent("CANCEL_LOOT_ROLL")
    loot:RegisterEvent("CHAT_MSG_LOOT")
    loot:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not (enabled() and cfg.lootRolls) then return end
        if event == "START_LOOT_ROLL" then
            StartRoll(arg1, arg2)
        elseif event == "CANCEL_LOOT_ROLL" then
            local rec = rollByID[arg1]
            if rec then Finish(rec); RefreshLootRolls() end
        else
            HandleLootMessage(arg1)
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit, spellName)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and spellName and spellName ~= "" then
                lastCastSpell = spellName
            end
            return
        elseif event == "SPELLS_CHANGED" then
            -- Your abilities changed, so a probe that found nothing might now
            -- succeed. Drop the back-off instead of waiting it out.
            InvalidateMeleeSpell()
            return
        end
        UpdateTrinkets()
    end)

    UpdateTrinkets()
    RefreshLootRolls()
end
