local ADDON, ns = ...

local M = ns.RegisterModule({
    key   = "delete",
    title = "Item Deletion",
    desc  = "Auto-fills the \"DELETE\" confirmation, or deletes instantly.",
})

ns.defaults.delete = {
    autoFill      = true,   -- pre-fill "DELETE" in the confirmation box
    instantDelete = false,  -- skip the confirmation dialog entirely
}

local cfg  -- filled in OnInit

-- Localized required confirmation word (e.g. "DELETE" on enUS clients).
local CONFIRM = DELETE_ITEM_CONFIRM_STRING or "DELETE"

-- Find the visible StaticPopup frame currently showing dialog `which`.
local function FindPopup(which)
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local frame = _G["StaticPopup" .. i]
        if frame and frame:IsShown() and frame.which == which then
            return frame, i
        end
    end
end

local function OnDeletePopup(which)
    if not ns.IsModuleEnabled("delete") then return end

    local frame, i = FindPopup(which)
    if not frame then return end

    if cfg.instantDelete then
        -- The item is on the cursor while the prompt is up; delete and dismiss.
        DeleteCursorItem()
        frame:Hide()
    elseif cfg.autoFill and which == "DELETE_GOOD_ITEM" then
        local editBox = frame.editBox or _G["StaticPopup" .. i .. "EditBox"]
        if editBox then
            editBox:SetText(CONFIRM)   -- fires OnTextChanged, which enables the confirm button
        end
    end
end

-- Options sub-page.
local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Item Deletion"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Item Deletion")

    local autoFill = ns.CreateCheck(panel, "Auto-fill \"DELETE\" in deletion prompts",
        "When deleting a quality item that asks you to type DELETE, the word is filled in automatically so you only need to click confirm.",
        cfg.autoFill)
    autoFill:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    autoFill:SetScript("OnClick", function(self)
        cfg.autoFill = self:GetChecked() and true or false
    end)

    local instant = ns.CreateCheck(panel, "Instant delete (skip the confirmation)",
        "|cffff2020Warning:|r deletes the item immediately with no confirmation dialog at all. Use with care.",
        cfg.instantDelete)
    instant:SetPoint("TOPLEFT", autoFill, "BOTTOMLEFT", 0, -8)
    instant:SetScript("OnClick", function(self)
        cfg.instantDelete = self:GetChecked() and true or false
    end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.config.delete

    -- StaticPopup_Show sets up and displays the dialog; hook runs right after,
    -- when the frame is shown and its edit box is ready.
    hooksecurefunc("StaticPopup_Show", function(which)
        if which == "DELETE_GOOD_ITEM" or which == "DELETE_ITEM" then
            OnDeletePopup(which)
        end
    end)

    BuildOptionsPanel()
end
