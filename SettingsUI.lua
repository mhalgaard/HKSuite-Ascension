local ADDON, ns = ...

-- =============================================================================
-- Settings UI -- HKSuite's own options window.
-- -----------------------------------------------------------------------------
-- Replaces the Blizzard Interface Options pages entirely. One standalone window:
-- a rail of modules down the left (each with its own on/off switch), the selected
-- module's settings on the right.
--
-- Two things live in here:
--
--   ns.UI    a small flat widget set (check, switch, input, text area, dropdown,
--            slider, button) plus a vertical-flow "page" that lays them out, so
--            modules describe their settings instead of hand-positioning frames.
--   the window itself, which owns the module rail, the per-module settings scope
--            control, and the "needs a reload" banner.
--
-- Everything is drawn from WHITE8X8 with 1px borders rather than Blizzard's frame
-- artwork -- that is what keeps it flat, and it is also the only way to get crisp
-- edges on a 3.3.5 client with no rounded-corner textures available.
--
-- A module opts in by setting `BuildSettings` on its module table:
--
--     function M:BuildSettings(page)
--         page:Header("Section")
--         page:Check{ label = "Do the thing", tooltip = "...",
--                     get = function() return cfg.thing end,
--                     set = function(v) cfg.thing = v end }
--     end
--
-- Pages are built the first time the module is selected, so a module that is
-- never opened costs nothing.
-- =============================================================================

local UI = {}
ns.UI = UI

-- ------------------------------------------------------------------- palette
local C = {
    window    = { 0.125, 0.125, 0.140, 0.97 },
    rail      = { 0.160, 0.160, 0.178, 1.00 },
    railSel   = { 1.000, 0.820, 0.000, 0.10 },
    border    = { 0.300, 0.300, 0.340, 1.00 },
    line      = { 1.000, 1.000, 1.000, 0.10 },
    field     = { 0.078, 0.078, 0.090, 0.95 },
    hover     = { 1.000, 1.000, 1.000, 0.07 },
    text      = { 0.900, 0.900, 0.915 },
    muted     = { 0.630, 0.630, 0.665 },
    dim       = { 0.470, 0.470, 0.495 },
    accent    = { 1.000, 0.820, 0.000 },
    off       = { 0.330, 0.330, 0.365 },
    warn      = { 1.000, 0.600, 0.200 },
    control   = { 0.215, 0.215, 0.240, 1.00 },   -- button face
    controlHi = { 0.290, 0.290, 0.320, 1.00 },
}
UI.colors = C

local FLAT = "Interface\\Buttons\\WHITE8X8"

-- Window metrics.
local WIN_W, WIN_H   = 800, 580
local RAIL_W         = 200
local TITLEBAR_H     = 36
local PAD            = 16
local PAGE_W         = WIN_W - RAIL_W - PAD * 2 - 14   -- 14 = scrollbar gutter

-- Row metrics shared by the widgets.
local ROW_GAP        = 10
local CHECK_SIZE     = 15
local FIELD_H        = 22
local INDENT         = 22

-- --------------------------------------------------------------- primitives
local function SetFlatBackdrop(f, bg, border, edge)
    f:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = border and FLAT or nil,
        edgeSize = edge or 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if bg then f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
    if border then f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
end
UI.SetFlatBackdrop = SetFlatBackdrop

local function Colorize(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- 3.3.5 has no SetWordWrap, so a wrapping FontString needs an explicit width and
-- reports its own height once laid out -- which is what the page flow relies on.
local function WrapText(fs, width)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
end

local function Tooltip(frame, text, anchor)
    if not text or text == "" then return end
    frame.hkTooltip = text
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(self.hkTooltip, nil, nil, nil, nil, true)
        GameTooltip:Show()
        if self.hkOnEnter then self:hkOnEnter() end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.hkOnLeave then self:hkOnLeave() end
    end)
end
UI.Tooltip = Tooltip

local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- UIPanelScrollFrameTemplate names its scrollbar "$parentScrollBar", so an
-- unnamed scroll frame leaves no way to reach the bar. Every one we make gets a
-- generated name for that reason alone.
local uid = 0
local function NextName(prefix)
    uid = uid + 1
    return "HKSuite" .. prefix .. uid
end

-- Strip the template's artwork down to a bare thumb: no step arrows, no track
-- art, just a thin bar that appears where the content overflows.
local function FlattenScrollBar(scrollName)
    local scroll = _G[scrollName]
    local bar = _G[scrollName .. "ScrollBar"]
    if not bar then return end

    -- Kill the step arrows. They are Buttons, but which frame owns them varies:
    -- Blizzard parents them to the scrollbar, this client's FrameXML parents them
    -- to the scroll frame and only anchors them to the bar -- so sweep both, by
    -- object type rather than by $parentScrollUpButton naming. Sweeping the
    -- scroll frame is safe because every caller flattens before adding any button
    -- of its own.
    --
    -- Hidden *and* transparent *and* mouse-dead: the scroll templates re-enable
    -- these as the range changes, and a client that re-shows them shouldn't be
    -- able to put them back on screen.
    local function killButtons(owner)
        if not (owner and owner.GetChildren) then return end
        for _, child in ipairs({ owner:GetChildren() }) do
            if child.GetObjectType and child:GetObjectType() == "Button" then
                child:Hide()
                child:SetAlpha(0)
                child:EnableMouse(false)
            end
        end
    end
    killButtons(bar)
    killButtons(scroll)

    for _, region in ipairs({ bar:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then region:SetTexture(nil) end
    end
    local thumb = bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture(FLAT)
        thumb:SetVertexColor(0.42, 0.42, 0.47, 0.85)
        thumb:SetSize(4, 50)
    end
    return bar
end

-- ============================== shared dropdown ==============================
-- One popup, reused by every dropdown on every page. Building it lazily keeps it
-- out of the way until something actually opens a menu.
local dropPopup

local function DropdownPopup()
    if dropPopup then return dropPopup end

    dropPopup = CreateFrame("Frame", "HKSuiteDropdownPopup", UIParent)
    dropPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    dropPopup:SetToplevel(true)
    SetFlatBackdrop(dropPopup, { 0.145, 0.145, 0.162, 0.98 }, C.border)
    dropPopup:Hide()
    dropPopup.rows = {}

    -- Click-off closes the menu.
    dropPopup:SetScript("OnShow", function(self)
        if not self.catcher then
            self.catcher = CreateFrame("Button", nil, UIParent)
            self.catcher:SetAllPoints(UIParent)
            self.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            self.catcher:SetFrameLevel(math.max(1, self:GetFrameLevel() - 1))
            self.catcher:SetScript("OnClick", function() dropPopup:Hide() end)
        end
        self.catcher:Show()
    end)
    dropPopup:SetScript("OnHide", function(self)
        if self.catcher then self.catcher:Hide() end
        if self.owner then self.owner:SetOpen(false) end
        self.owner = nil
    end)

    return dropPopup
end

local function DropdownRow(popup, i)
    local row = popup.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, popup)
    row:SetHeight(20)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(FLAT)
    row.bg:SetVertexColor(1, 1, 1, 0)

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetJustifyH("LEFT")

    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(FLAT)
    row.tick:SetSize(3, 12)
    row.tick:SetPoint("LEFT", 2, 0)
    row.tick:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])

    row:SetScript("OnEnter", function(self) self.bg:SetVertexColor(1, 1, 1, 0.08) end)
    row:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0) end)

    popup.rows[i] = row
    return row
end

local function OpenDropdown(widget)
    local popup = DropdownPopup()
    if popup:IsShown() and popup.owner == widget then
        popup:Hide()
        return
    end

    popup.owner = widget
    local options, current = widget.options, widget.get and widget.get()
    local width = math.max(widget.button:GetWidth(), 120)
    local y = -4

    for i, opt in ipairs(options) do
        local row = DropdownRow(popup, i)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, y)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, y)
        row.text:SetText(opt[2])
        if opt[3] then Colorize(row.text, opt[3]) else Colorize(row.text, C.text) end
        if opt[1] == current then row.tick:Show() else row.tick:Hide() end
        row:SetScript("OnClick", function()
            popup:Hide()
            widget:SetValue(opt[1])
        end)
        row:Show()
        y = y - 20
    end
    for i = #options + 1, #popup.rows do popup.rows[i]:Hide() end

    popup:SetSize(width, -y + 4)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", widget.button, "BOTTOMLEFT", 0, -2)
    popup:Show()
    widget:SetOpen(true)
end

-- ================================== widgets ==================================
-- Each constructor returns a frame carrying its own height, so the page flow can
-- stack them without knowing what any of them are.

-- A flat check: a bordered box that fills with the accent colour when on.
-- Every widget below is a wrapper frame holding the real control. The wrapper
-- MUST be given a width: a frame whose rect can't be resolved is not drawn, and
-- neither is anything parented to it, so a wrapper left at zero width takes its
-- input/dropdown/slider down with it.
local function MakeCheck(parent, opts)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(opts.width or 240, math.max(CHECK_SIZE, 18))

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(CHECK_SIZE, CHECK_SIZE)
    box:SetPoint("LEFT", 0, 0)
    SetFlatBackdrop(box, C.field, C.border)
    f.box = box

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(FLAT)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    f.fill = fill

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")
    f.label = label

    f.get, f.set, f.onChange = opts.get, opts.set, opts.onChange
    f.children = {}

    function f:Refresh()
        local on = self.get and self.get() and true or false
        if on then self.fill:Show() else self.fill:Hide() end
        local c = self.dimmed and C.dim or C.text
        Colorize(self.label, c)
    end

    function f:SetDimmed(v)
        self.dimmed = v and true or false
        self:Refresh()
    end

    -- Sub-options grey out with their parent but stay clickable, matching how the
    -- old panels behaved.
    function f:BindChildren(list)
        self.children = list or {}
        self:RefreshChildren()
    end

    function f:RefreshChildren()
        local on = self.get and self.get() and true or false
        for _, child in ipairs(self.children) do
            if child.SetDimmed then child:SetDimmed(not on) end
        end
    end

    f:SetScript("OnClick", function(self)
        local on = not (self.get and self.get())
        if self.set then self.set(on and true or false) end
        self:Refresh()
        self:RefreshChildren()
        if self.onChange then self.onChange(on and true or false) end
    end)

    f.hkOnEnter = function(self) self.box:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3]) end
    f.hkOnLeave = function(self) self.box:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3]) end
    Tooltip(f, opts.tooltip)
    if not opts.tooltip then
        f:SetScript("OnEnter", function(self) self:hkOnEnter() end)
        f:SetScript("OnLeave", function(self) self:hkOnLeave() end)
    end

    f:Refresh()
    return f
end

-- A sliding switch, used for the module on/off toggles in the rail.
local function MakeSwitch(parent, opts)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(26, 14)

    local track = CreateFrame("Frame", nil, f)
    track:SetAllPoints()
    SetFlatBackdrop(track, C.off, C.border)
    f.track = track

    local knob = track:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(FLAT)
    knob:SetSize(10, 10)
    f.knob = knob

    f.get, f.set, f.onChange = opts.get, opts.set, opts.onChange

    function f:Refresh()
        local on = self.get and self.get() and true or false
        self.knob:ClearAllPoints()
        if on then
            self.track:SetBackdropColor(C.accent[1] * 0.55, C.accent[2] * 0.55, 0, 1)
            self.knob:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            self.knob:SetPoint("RIGHT", self.track, "RIGHT", -2, 0)
        else
            self.track:SetBackdropColor(C.off[1], C.off[2], C.off[3], 1)
            self.knob:SetVertexColor(0.55, 0.55, 0.58)
            self.knob:SetPoint("LEFT", self.track, "LEFT", 2, 0)
        end
    end

    f:SetScript("OnClick", function(self)
        local on = not (self.get and self.get())
        if self.set then self.set(on and true or false) end
        self:Refresh()
        if self.onChange then self.onChange(on and true or false) end
    end)

    f:Refresh()
    return f
end

-- Flat single-line input. `numeric` clamps to [min,max] on commit.
local function MakeInput(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 160, FIELD_H)

    local box = CreateFrame("EditBox", opts.name, f)
    box:SetHeight(FIELD_H)
    box:SetWidth(opts.width or 160)
    box:SetPoint("LEFT", 0, 0)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 22, 0, 0)   -- right inset leaves room for the accept tick
    SetFlatBackdrop(box, C.field, C.border)
    f.box = box

    f.get, f.set, f.onChange = opts.get, opts.set, opts.onChange

    local function Current()
        local v = f.get and f.get()
        return v == nil and "" or tostring(v)
    end

    function f:Commit()
        local text = Trim(box:GetText())
        if opts.numeric then
            local v = tonumber(text:match("-?[%d%.]+") or "") or opts.min or 0
            if opts.min and v < opts.min then v = opts.min end
            if opts.max and v > opts.max then v = opts.max end
            if opts.step == 1 then v = math.floor(v + 0.5) end
            if self.set then self.set(v) end
        else
            if text == "" and opts.fallback then text = opts.fallback end
            if self.set then self.set(text) end
        end
        box:SetText(Current())
        if self.onChange then self.onChange() end
    end

    function f:Refresh() box:SetText(Current()) end

    box:SetScript("OnEnterPressed", function(self) f:Commit(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function() f:Commit() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(Current()); self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    box:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3])
    end)

    ns.CreateInlineAccept(box, function() f:Commit() end)

    f:Refresh()
    return f
end

-- Multi-line editor for the whitelist-style settings.
local function MakeTextArea(parent, opts)
    local height = opts.height or 96
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or (PAGE_W - 30), height)

    local scrollName = NextName("TextArea")
    local frame = CreateFrame("ScrollFrame", scrollName, f, "UIPanelScrollFrameTemplate")
    frame:SetPoint("TOPLEFT", 0, 0)
    frame:SetSize(opts.width or (PAGE_W - 30), height)
    SetFlatBackdrop(frame, C.field, C.border)
    f.scroll = frame

    local bar = FlattenScrollBar(scrollName)
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -4)
        bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 4)
    end

    local edit = CreateFrame("EditBox", opts.name, frame)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth((opts.width or (PAGE_W - 30)) - 18)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(6, 6, 5, 5)
    frame:SetScrollChild(edit)
    f.edit = edit

    f.get, f.set, f.onChange = opts.get, opts.set, opts.onChange

    function f:Refresh() edit:SetText(f.get and f.get() or "") end

    function f:Commit()
        if self.set then self.set(edit:GetText() or "") end
        if self.onChange then self.onChange() end
    end

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function() f:Commit() end)

    ns.CreateInlineAccept(edit, function() f:Commit() end, frame, "TOPRIGHT", -10, -6)

    f:Refresh()
    return f
end

-- Flat dropdown: a bordered button plus the shared popup.
local function MakeDropdown(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 150, FIELD_H)

    local btn = CreateFrame("Button", nil, f)
    btn:SetHeight(FIELD_H)
    btn:SetWidth(opts.width or 150)
    btn:SetPoint("LEFT", 0, 0)
    SetFlatBackdrop(btn, C.field, C.border)
    f.button = btn

    local text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -18, 0)
    text:SetJustifyH("LEFT")
    f.text = text

    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -3, 0)
    arrow:SetVertexColor(0.7, 0.7, 0.7)

    f.options, f.get, f.set, f.onChange = opts.options or {}, opts.get, opts.set, opts.onChange

    function f:Refresh()
        local v = self.get and self.get()
        for _, opt in ipairs(self.options) do
            if opt[1] == v then
                self.text:SetText(opt[2])
                Colorize(self.text, opt[3] or C.text)
                return
            end
        end
        self.text:SetText(self.options[1] and self.options[1][2] or "")
        Colorize(self.text, C.muted)
    end

    function f:SetValue(v)
        if self.set then self.set(v) end
        self:Refresh()
        if self.onChange then self.onChange(v) end
    end

    function f:SetOpen(open)
        if open then
            btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3])
        else
            btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3])
        end
    end

    btn:SetScript("OnClick", function() OpenDropdown(f) end)
    btn:SetScript("OnEnter", function(self)
        if not (dropPopup and dropPopup:IsShown() and dropPopup.owner == f) then
            self:SetBackdropBorderColor(0.4, 0.4, 0.45)
        end
        if opts.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not (dropPopup and dropPopup:IsShown() and dropPopup.owner == f) then
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3])
        end
        GameTooltip:Hide()
    end)

    f:Refresh()
    return f
end

-- Flat slider with the value written into its own label.
local function MakeSlider(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 220, 38)

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label

    local slider = CreateFrame("Slider", opts.name, f)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(opts.width or 220, 14)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 100)
    slider:SetValueStep(opts.step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    f.slider = slider

    local track = CreateFrame("Frame", nil, slider)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetFrameLevel(math.max(0, slider:GetFrameLevel() - 1))
    SetFlatBackdrop(track, C.field, C.border)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(FLAT)
    thumb:SetSize(8, 14)
    thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    slider:SetThumbTexture(thumb)

    f.get, f.set, f.onChange = opts.get, opts.set, opts.onChange
    local format = opts.format or function(v) return tostring(v) end

    local function Snap(v)
        local step = opts.step or 1
        return math.floor(v / step + 0.5) * step
    end

    function f:Refresh()
        local v = (self.get and self.get()) or opts.min or 0
        self.applying = true            -- SetValue fires OnValueChanged
        slider:SetValue(v)
        self.applying = false
        label:SetText((opts.label or "") .. "  |cffffd100" .. format(v) .. "|r")
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if f.applying then return end
        value = Snap(value)
        if f.set then f.set(value) end
        label:SetText((opts.label or "") .. "  |cffffd100" .. format(value) .. "|r")
        if f.onChange then f.onChange(value) end
    end)

    Tooltip(slider, opts.tooltip)
    f:Refresh()
    return f
end

-- Flat button.
local function MakeButton(parent, opts)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(opts.width or 180, opts.height or 24)
    SetFlatBackdrop(f, C.control, C.border)

    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(opts.text or "")
    f.text = text

    f:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.controlHi[1], C.controlHi[2], C.controlHi[3], 1)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3])
        if opts.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.control[1], C.control[2], C.control[3], 1)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3])
        GameTooltip:Hide()
    end)
    if opts.onClick then f:SetScript("OnClick", opts.onClick) end

    return f
end

-- ================================== the page =================================
-- A vertical flow: every Add* call drops its widget below the last one and moves
-- the cursor down. `indent` shifts a widget right so sub-options read as nested.

local Page = {}
Page.__index = Page

-- Widget options take `indent = true`; Text/Hint/_Place take a level. The two got
-- mixed up often enough -- `true * INDENT` is a runtime error, and it takes a
-- settings page down with it -- that accepting either is worth the three lines.
local function IndentX(indent)
    if indent == true then return INDENT end
    return (tonumber(indent) or 0) * INDENT
end

function Page:_Place(widget, indent, gap)
    widget:ClearAllPoints()
    local x = IndentX(indent)
    widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
    -- Checks claim the whole row: the wrapper is their click target, so a full
    -- width means clicking anywhere on the line toggles them. Anything else keeps
    -- the width its constructor chose, and a zero width is repaired rather than
    -- silently swallowing the widget.
    if widget.autoWidth or widget:GetWidth() <= 0 then
        widget:SetWidth(self.width - x)
    end
    self.y = self.y - widget:GetHeight() - (gap or ROW_GAP)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

function Page:Header(text)
    local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    Colorize(fs, C.accent)
    self.y = self.y - 6
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y)
    self.y = self.y - fs:GetStringHeight() - 8

    local rule = self.content:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    rule:SetSize(self.width, 1)
    rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y + 4)
    self.y = self.y - 6
    return fs
end

-- ------------------------------------------------------------------ sections
-- A collapsible block: a header that folds its contents away, with the feature's
-- own on/off switch sitting in the header itself. Pages that describe several
-- sizeable features (UI Features runs to four) are unreadable as one flat scroll.
--
-- A section's contents go into a container frame of their own rather than onto
-- the page flow, so folding one is only hiding that frame and re-anchoring the
-- sections below it. The consequence: once a page opens its first section,
-- everything after it has to live inside a section too.
local SECTION_H, SECTION_GAP = 24, 8

function Page:Section(opts)
    self:_CloseSection()
    if not self.sections[1] then self.sectionsY = self.y end

    local page = self
    local section = { collapsed = opts.collapsed ~= false }

    local header = CreateFrame("Button", nil, self.pageContent)
    header:SetSize(self.width, SECTION_H)

    -- The fold marker is drawn rather than borrowed: two accent bars in the same
    -- flat square the checkboxes use, minus when open and plus when shut. Blizzard's
    -- +/- button art would be the only bevelled thing in the window.
    local glyph = CreateFrame("Frame", nil, header)
    glyph:SetSize(CHECK_SIZE, CHECK_SIZE)
    glyph:SetPoint("LEFT", 0, 1)
    SetFlatBackdrop(glyph, C.field, C.border)
    section.glyph = glyph

    local function Bar(w, h)
        local bar = glyph:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(FLAT)
        bar:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        bar:SetSize(w, h)
        bar:SetPoint("CENTER")
        return bar
    end
    Bar(CHECK_SIZE - 6, 2)                  -- always there: the minus
    section.stem = Bar(2, CHECK_SIZE - 6)   -- shown only when shut: makes it a plus

    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("LEFT", CHECK_SIZE + 8, 1)
    title:SetText(opts.title or "")
    Colorize(title, C.accent)

    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)

    header:SetScript("OnEnter", function()
        Colorize(title, C.text)
        glyph:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    header:SetScript("OnLeave", function()
        Colorize(title, C.accent)
        glyph:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3])
    end)
    header:SetScript("OnClick", function()
        section.collapsed = not section.collapsed
        page:_LayoutSections()
    end)
    self.widgets[#self.widgets + 1] = header

    -- The feature's own switch, on the header rather than as the first line
    -- inside: it stays reachable with the section folded shut.
    if opts.get then
        local check = MakeCheck(header, {
            label = opts.checkLabel or "Enabled", tooltip = opts.tooltip, width = 100,
            get = opts.get, set = opts.set, onChange = opts.onChange,
        })
        check:ClearAllPoints()
        check:SetPoint("RIGHT", header, "RIGHT", 0, 1)
        check:SetFrameLevel(header:GetFrameLevel() + 2)
        section.check = check
        self.widgets[#self.widgets + 1] = check
    end

    local body = CreateFrame("Frame", nil, self.pageContent)
    body:SetSize(self.width, 1)
    section.header, section.body = header, body
    -- Anything placed from here on lands in the body, measured from its own top.
    section.widgetStart = #self.widgets + 1
    self.sections[#self.sections + 1] = section
    self.section = section
    self.content = body
    self.y = -SECTION_GAP

    return section
end

function Page:_CloseSection()
    local section = self.section
    if not section then return end

    section.height = -self.y
    section.body:SetHeight(math.max(1, section.height))
    self.section = nil
    self.content = self.pageContent

    -- Everything the section placed dims with its switch, for free.
    if section.check then
        local children = {}
        for i = section.widgetStart, #self.widgets do
            children[#children + 1] = self.widgets[i]
        end
        section.check:BindChildren(children)
    end

    self:_LayoutSections()
end

function Page:_LayoutSections()
    local y = self.sectionsY or 0
    for _, section in ipairs(self.sections) do
        section.header:ClearAllPoints()
        section.header:SetPoint("TOPLEFT", self.pageContent, "TOPLEFT", 0, y)
        y = y - SECTION_H

        section.body:ClearAllPoints()
        section.body:SetPoint("TOPLEFT", self.pageContent, "TOPLEFT", 0, y)
        if section.collapsed then
            section.body:Hide()
        else
            section.body:Show()
            y = y - (section.height or 0)
        end
        y = y - SECTION_GAP

        if section.collapsed then section.stem:Show() else section.stem:Hide() end
    end
    self.y = y
    self.pageContent:SetHeight(math.max(1, -y + PAD))
end

function Page:Text(text, indent)
    local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local x = IndentX(indent)
    WrapText(fs, self.width - x)
    fs:SetText(text)
    Colorize(fs, C.muted)
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
    self.y = self.y - fs:GetStringHeight() - ROW_GAP
    return fs
end

function Page:Hint(text, indent)
    local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local x = IndentX(indent)
    WrapText(fs, self.width - x)
    fs:SetText(text)
    Colorize(fs, C.dim)
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
    self.y = self.y - fs:GetStringHeight() - ROW_GAP
    return fs
end

function Page:Divider()
    local rule = self.content:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    rule:SetSize(self.width, 1)
    self.y = self.y - 4
    rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y)
    self.y = self.y - 10
    return rule
end

function Page:Spacer(h)
    self.y = self.y - (h or 8)
end

function Page:Check(opts)
    local w = MakeCheck(self.content, opts)
    w.autoWidth = true
    return self:_Place(w, opts.indent and 1 or 0, opts.gap or 6)
end

function Page:Input(opts)
    -- A labelled input gets its caption on the line above, so long captions never
    -- squeeze the field.
    if opts.label then
        local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        local x = (opts.indent and 1 or 0) * INDENT
        WrapText(fs, self.width - x)
        fs:SetText(opts.label)
        Colorize(fs, C.text)
        fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
        self.y = self.y - fs:GetStringHeight() - 5
    end
    local w = MakeInput(self.content, opts)
    return self:_Place(w, opts.indent and 1 or 0, opts.gap)
end

function Page:TextArea(opts)
    if opts.label then
        local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        WrapText(fs, self.width)
        fs:SetText(opts.label)
        Colorize(fs, C.text)
        fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y)
        self.y = self.y - fs:GetStringHeight() - 5
    end
    opts.width = opts.width or self.width
    local w = MakeTextArea(self.content, opts)
    return self:_Place(w, 0, opts.gap)
end

function Page:Dropdown(opts)
    if opts.label then
        local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        local x = (opts.indent and 1 or 0) * INDENT
        WrapText(fs, self.width - x)
        fs:SetText(opts.label)
        Colorize(fs, C.text)
        fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
        self.y = self.y - fs:GetStringHeight() - 5
    end
    local w = MakeDropdown(self.content, opts)
    return self:_Place(w, opts.indent and 1 or 0, opts.gap)
end

function Page:Slider(opts)
    local w = MakeSlider(self.content, opts)
    return self:_Place(w, opts.indent and 1 or 0, opts.gap)
end

function Page:Button(opts)
    local w = MakeButton(self.content, opts)
    return self:_Place(w, opts.indent and 1 or 0, opts.gap)
end

-- A row of widgets side by side. `items` is a list of {kind = "button"/"dropdown"
-- /"check", ...opts}; each is built and placed left to right.
function Page:Row(items, opts)
    opts = opts or {}
    local gap = opts.spacing or 8
    local x = (opts.indent and 1 or 0) * INDENT
    local tallest, built = 0, {}

    for _, item in ipairs(items) do
        local w
        if item.kind == "dropdown" then w = MakeDropdown(self.content, item)
        elseif item.kind == "check" then w = MakeCheck(self.content, item)
        elseif item.kind == "input" then w = MakeInput(self.content, item)
        else w = MakeButton(self.content, item) end
        if w:GetWidth() <= 0 then w:SetWidth(item.width or 200) end
        built[#built + 1] = { w, item }
        tallest = math.max(tallest, w:GetHeight())
    end

    for _, entry in ipairs(built) do
        local w = entry[1]
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
        x = x + w:GetWidth() + gap
        self.widgets[#self.widgets + 1] = w
    end

    self.y = self.y - tallest - (opts.gap or ROW_GAP)
    local out = {}
    for i, entry in ipairs(built) do out[i] = entry[1] end
    return out
end

-- A labelled grid of dropdowns -- what the quality/override tables need.
function Page:Grid(columns, items, opts)
    opts = opts or {}
    local colW = math.floor(self.width / columns)
    local startY = self.y
    local rowHeight = 0

    for i, item in ipairs(items) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local x = col * colW
        local y = startY - row * (rowHeight > 0 and rowHeight or 46)

        local fs = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
        fs:SetText(item.label)
        Colorize(fs, item.color or C.text)

        local dd = MakeDropdown(self.content, {
            width = colW - 12, options = item.options,
            get = item.get, set = item.set, onChange = item.onChange,
        })
        dd:ClearAllPoints()
        dd:SetWidth(colW - 12)
        dd:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y - fs:GetStringHeight() - 4)
        self.widgets[#self.widgets + 1] = dd
        rowHeight = fs:GetStringHeight() + 4 + dd:GetHeight() + 12
    end

    local rows = math.ceil(#items / columns)
    self.y = startY - rows * rowHeight - (opts.gap or 4)
end

-- Register extra work to run whenever the page is shown -- for anything a widget
-- can't refresh on its own, like a status line reporting live client state.
function Page:OnRefresh(fn)
    self.refreshers[#self.refreshers + 1] = fn
    fn()
end

-- Pages are built once and kept, so a value changed elsewhere (a slash command,
-- another page, a reload-scope switch) would otherwise show stale on return.
function Page:Refresh()
    for _, w in ipairs(self.widgets) do
        if w.Refresh then w:Refresh() end
    end
    for _, w in ipairs(self.widgets) do
        if w.RefreshChildren then w:RefreshChildren() end
    end
    for _, fn in ipairs(self.refreshers) do pcall(fn) end
end

-- Called once the module has finished describing itself: sizes the scroll child
-- so the scrollbar knows how far it can go.
function Page:Finish()
    self:_CloseSection()
    self.pageContent:SetHeight(math.max(1, -self.y + PAD))
end

function UI.CreatePage(parent, width)
    local page = setmetatable({}, Page)
    page.width = width or PAGE_W
    page.y = 0
    page.widgets = {}
    page.refreshers = {}
    page.sections = {}
    page.content = CreateFrame("Frame", nil, parent)
    page.content:SetWidth(page.width)
    page.content:SetHeight(1)
    page.pageContent = page.content   -- where the page flow lives, sections aside
    return page
end

-- ================================ the window =================================
local window, rail, railRows, contentHost, pageHeader, pageDesc, scopeRow, banner
local pages = {}        -- module key (or "overview") -> page
local currentKey

local reloadNeeded = false

-- Modules capture their config table and hook their events once, at load, so a
-- module switched on mid-session generally cannot start working until a reload.
-- Rather than guess, a module says so with `reloadOnToggle`.
function ns.MarkReloadNeeded(reason)
    reloadNeeded = true
    if banner then
        banner.text:SetText(reason or "Some changes need a UI reload to take effect.")
        banner:Show()
    end
end

local function ModuleList()
    local mods = {}
    for _, m in ipairs(ns.modules) do
        if m.key and m.title then mods[#mods + 1] = m end
    end
    return mods
end

local function SelectPage(key)
    currentKey = key
    for _, row in ipairs(railRows) do
        local selected = (row.key == key)
        row.sel:SetAlpha(selected and 1 or 0)
        row.bg:SetVertexColor(1, 1, 1, selected and 0.05 or 0)
        Colorize(row.label, selected and C.text or C.muted)
    end

    for k, page in pairs(pages) do
        if k == key then
            page.content:GetParent():Show()
            page:Refresh()
        else
            page.content:GetParent():Hide()
        end
    end
end

-- Each module page opens with the account/per-character control, because the
-- scope belongs to the module but is not the module's business to draw.
local function BuildScopeRow(parent, module)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PAGE_W, FIELD_H)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText("Settings:")
    Colorize(label, C.muted)

    local dd = MakeDropdown(row, {
        width = 150,
        options = { { "account", "Shared (account-wide)" }, { "character", "This character only" } },
        get = function() return ns.GetScope(module.key) end,
        set = function(v) ns.SetScope(module.key, v) end,
        onChange = function()
            ns.MarkReloadNeeded("Settings scope changed -- reload to apply it.")
        end,
        tooltip = "Shared: this module reads the account-wide settings.\n\n"
            .. "This character only: this character keeps its own copy, seeded from the "
            .. "account settings the first time you switch.\n\nApplies after a reload.",
    })
    dd:SetPoint("LEFT", label, "RIGHT", 8, 0)
    row.dropdown = dd
    return row
end

local function BuildPage(module)
    local key = module and module.key or "overview"
    if pages[key] then return pages[key] end

    local scrollName = NextName("Page")
    local scroll = CreateFrame("ScrollFrame", scrollName, contentHost, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)

    local bar = FlattenScrollBar(scrollName)
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    end

    local page = UI.CreatePage(scroll, PAGE_W)
    scroll:SetScrollChild(page.content)
    page.scroll = scroll
    page.module = module

    if module then
        local scope = BuildScopeRow(page.content, module)
        scope:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, page.y)
        page.y = page.y - scope:GetHeight() - 14
        page.scopeRow = scope
    end

    if module and module.BuildSettings then
        local ok, err = pcall(module.BuildSettings, module, page)
        if not ok then
            -- The module may have died mid-section, which would drop the message
            -- into a body that is folded shut. Close it first so it's readable.
            page:_CloseSection()
            page:Text("|cffff4040This module's settings failed to build:|r " .. tostring(err))
        end
    elseif not module then
        ns.BuildOverviewPage(page)
    else
        page:Text("This module has no settings.")
    end

    page:Finish()
    pages[key] = page
    return page
end

local function ShowModule(module)
    local key = module and module.key or "overview"
    BuildPage(module)

    pageHeader:SetText(module and module.title or ("HKSuite  |cff808080"
        .. ((GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or ns.version) .. "|r"))
    pageDesc:SetText(module and (module.desc or "") or "Every module in the suite, and what it does.")

    SelectPage(key)
end

local function BuildRail()
    railRows = {}
    local mods = ModuleList()

    local function AddRow(index, module)
        local key = module and module.key or "overview"
        local row = CreateFrame("Button", nil, rail)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -8 - (index - 1) * 26)
        row:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, -8 - (index - 1) * 26)
        row.key = key

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture(FLAT)
        row.bg:SetVertexColor(1, 1, 1, 0)

        -- Selection is a thin accent bar rather than a filled row.
        row.sel = row:CreateTexture(nil, "ARTWORK")
        row.sel:SetTexture(FLAT)
        row.sel:SetSize(2, 26)
        row.sel:SetPoint("LEFT", 0, 0)
        row.sel:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        row.sel:SetAlpha(0)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 12, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(module and module.title or "Overview")
        Colorize(row.label, C.muted)

        if module then
            local sw = MakeSwitch(row, {
                get = function() return ns.IsModuleEnabled(key) end,
                set = function(v) ns.SetModuleEnabled(key, v) end,
                onChange = function(on)
                    if module.OnToggle then pcall(module.OnToggle, module, on) end
                    if module.reloadOnToggle then
                        ns.MarkReloadNeeded("Enabling or disabling |cffffd100" .. module.title
                            .. "|r needs a UI reload to take effect.")
                    end
                end,
            })
            sw:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.switch = sw
            row.label:SetPoint("RIGHT", sw, "LEFT", -8, 0)
            Tooltip(sw, "Turn " .. module.title .. " on or off."
                .. (module.reloadOnToggle and "\n\n|cffff9933Needs a UI reload to take effect.|r" or ""))
        end

        row:SetScript("OnClick", function() ShowModule(module) end)
        row:SetScript("OnEnter", function(self)
            if self.key ~= currentKey then self.bg:SetVertexColor(1, 1, 1, 0.04) end
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetVertexColor(1, 1, 1, self.key == currentKey and 0.05 or 0)
        end)

        railRows[#railRows + 1] = row
        return row
    end

    AddRow(1, nil)                     -- Overview

    -- A hairline under the Overview entry separates it from the module list.
    local sep = rail:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(FLAT)
    sep:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    sep:SetPoint("TOPLEFT", rail, "TOPLEFT", 10, -36)
    sep:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -10, -36)
    sep:SetHeight(1)

    for i, module in ipairs(mods) do AddRow(i + 2, module) end
end

local function RefreshRail()
    for _, row in ipairs(railRows) do
        if row.switch then row.switch:Refresh() end
    end
end

local function BuildWindow()
    window = CreateFrame("Frame", "HKSuiteSettingsFrame", UIParent)
    window:SetSize(WIN_W, WIN_H)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetClampedToScreen(true)
    SetFlatBackdrop(window, C.window, C.border)
    window:Hide()

    tinsert(UISpecialFrames, "HKSuiteSettingsFrame")   -- Escape closes it

    -- ---- title bar ----
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLEBAR_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() window:StartMoving() end)
    bar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    local barLine = bar:CreateTexture(nil, "ARTWORK")
    barLine:SetTexture(FLAT)
    barLine:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    barLine:SetPoint("BOTTOMLEFT", 1, 0)
    barLine:SetPoint("BOTTOMRIGHT", -1, 0)
    barLine:SetHeight(1)

    local brand = bar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    brand:SetPoint("LEFT", PAD, 0)
    brand:SetText("HKSuite")
    Colorize(brand, C.accent)

    local byline = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    byline:SetPoint("LEFT", brand, "RIGHT", 6, -1)
    byline:SetText("by " .. ns.author)
    Colorize(byline, C.muted)

    local close = CreateFrame("Button", nil, bar)
    close:SetSize(TITLEBAR_H - 12, TITLEBAR_H - 12)
    close:SetPoint("RIGHT", -8, 0)
    local x = close:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    x:SetPoint("CENTER")
    x:SetText("x")
    Colorize(x, C.muted)
    close:SetScript("OnEnter", function() Colorize(x, C.accent) end)
    close:SetScript("OnLeave", function() Colorize(x, C.muted) end)
    close:SetScript("OnClick", function() window:Hide() end)

    -- ---- left rail ----
    rail = CreateFrame("Frame", nil, window)
    rail:SetPoint("TOPLEFT", 0, -TITLEBAR_H)
    rail:SetPoint("BOTTOMLEFT", 0, 0)
    rail:SetWidth(RAIL_W)
    SetFlatBackdrop(rail, C.rail)

    local railLine = rail:CreateTexture(nil, "ARTWORK")
    railLine:SetTexture(FLAT)
    railLine:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    railLine:SetPoint("TOPRIGHT", 0, 0)
    railLine:SetPoint("BOTTOMRIGHT", 0, 0)
    railLine:SetWidth(1)

    -- ---- page header ----
    pageHeader = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    pageHeader:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + PAD, -TITLEBAR_H - PAD)
    pageHeader:SetJustifyH("LEFT")

    pageDesc = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageDesc:SetPoint("TOPLEFT", pageHeader, "BOTTOMLEFT", 0, -5)
    WrapText(pageDesc, PAGE_W)
    Colorize(pageDesc, C.muted)

    local headRule = window:CreateTexture(nil, "ARTWORK")
    headRule:SetTexture(FLAT)
    headRule:SetVertexColor(C.line[1], C.line[2], C.line[3], C.line[4])
    headRule:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + PAD, -TITLEBAR_H - 74)
    headRule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -TITLEBAR_H - 74)
    headRule:SetHeight(1)

    -- ---- reload banner (bottom, only while a reload is pending) ----
    banner = CreateFrame("Frame", nil, window)
    banner:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", RAIL_W + PAD, PAD)
    banner:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)
    banner:SetHeight(30)
    SetFlatBackdrop(banner, { 0.18, 0.11, 0.02, 1 }, { 0.45, 0.32, 0.05, 1 })
    banner:Hide()

    banner.text = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    banner.text:SetPoint("LEFT", 10, 0)
    banner.text:SetJustifyH("LEFT")
    Colorize(banner.text, C.warn)

    local reloadBtn = MakeButton(banner, {
        text = "Reload UI", width = 92, height = 20,
        onClick = function() ReloadUI() end,
    })
    reloadBtn:SetPoint("RIGHT", -8, 0)
    banner.text:SetPoint("RIGHT", reloadBtn, "LEFT", -10, 0)

    -- ---- content host ----
    contentHost = CreateFrame("Frame", nil, window)
    contentHost:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + PAD, -TITLEBAR_H - 84)
    contentHost:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)

    -- Keep the content clear of the banner while it is up.
    banner:SetScript("OnShow", function()
        contentHost:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD + 38)
    end)
    banner:SetScript("OnHide", function()
        contentHost:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)
    end)

    BuildRail()

    window:SetScript("OnShow", function()
        RefreshRail()
        if reloadNeeded then banner:Show() end
    end)
end

function ns.OpenSettings(key)
    if not window then BuildWindow() end
    window:Show()
    if key then
        for _, m in ipairs(ns.modules) do
            if m.key == key then ShowModule(m); return end
        end
    end
    if not currentKey then ShowModule(nil) end
end

function ns.ToggleSettings()
    if window and window:IsShown() then
        window:Hide()
    else
        ns.OpenSettings()
    end
end
