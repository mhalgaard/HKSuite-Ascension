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

-- The settings page. It is built the first time the module is selected in the
-- settings window; see ns.UI for everything a page can hold.
function M:BuildSettings(page)
    page:Header("Section")

    -- page:Check({
    --     label = "Do the thing",
    --     tooltip = "Tooltip text.",
    --     get = function() return cfg.enabledThing end,
    --     set = function(v) cfg.enabledThing = v end,
    -- })
    --
    -- page:Input({ label = "A value", width = 120,
    --     get = function() return cfg.value end,
    --     set = function(v) cfg.value = v end })
    --
    -- page:Button({ text = "Do it now", onClick = function() end })
end

function M:OnInit()
    cfg = ns.GetConfig("scratch")

    -- Register events and guard behavior behind the module toggle:
    -- local frame = CreateFrame("Frame")
    -- frame:RegisterEvent("SOME_EVENT")
    -- frame:SetScript("OnEvent", function(_, event, ...)
    --     if ns.IsModuleEnabled("scratch") then
    --         -- handle event
    --     end
    -- end)
end

--]]
