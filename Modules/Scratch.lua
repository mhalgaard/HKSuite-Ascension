local ADDON, ns = ...

-- =============================================================================
-- SCRATCH / PROTOTYPE MODULE
-- -----------------------------------------------------------------------------
-- This file is permanently listed in HKSuite.toc, so it is ALWAYS loaded. That
-- means you can prototype a new module here and pick up changes with just
-- /reload in-game -- no client restart needed.
--
-- Workflow:
--   1. Fill in the template below and iterate with /reload.
--   2. When the module is finished, move it to its own Modules/<Name>.lua,
--      add that file to HKSuite.toc, and clear this file back to the template.
--      (That final step needs one restart, and can be batched with other new
--      modules.)
--
-- While empty (template commented out), this file does nothing.
-- =============================================================================

--[[  TEMPLATE -- uncomment and rename to start prototyping:

local M = ns.RegisterModule({
    key   = "scratch",                          -- unique id
    title = "Scratch Module",                   -- shown on the Overview page
    desc  = "Prototype module (work in progress).",
})

ns.defaults.scratch = {
    -- your options here, e.g.:
    -- enabledThing = true,
}

local cfg  -- filled in OnInit

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Scratch Module"
    panel.parent = "HKSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Scratch Module")

    -- Example checkbox:
    -- local cb = ns.CreateCheck(panel, "Do the thing", "Tooltip text.", cfg.enabledThing)
    -- cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    -- cb:SetScript("OnClick", function(self) cfg.enabledThing = self:GetChecked() and true or false end)

    InterfaceOptions_AddCategory(panel)
end

function M:OnInit()
    cfg = ns.config.scratch

    -- Register events and guard behavior behind the module toggle:
    -- local frame = CreateFrame("Frame")
    -- frame:RegisterEvent("SOME_EVENT")
    -- frame:SetScript("OnEvent", function(_, event, ...)
    --     if ns.IsModuleEnabled("scratch") then
    --         -- handle event
    --     end
    -- end)

    BuildOptionsPanel()
end

--]]
