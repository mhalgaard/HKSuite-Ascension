local ADDON, ns = ...

local PROFILE_NAME = "default"

-- Switch an AceDB-based addon to `profile`, but only if that profile exists
-- (AceDB would otherwise silently create an empty one and wipe the layout).
local function SetAceProfile(db, profile)
    if not (db and db.GetProfiles and db.SetProfile) then return "no profile API" end
    local target = profile:lower()
    local match
    for _, name in ipairs(db:GetProfiles()) do
        if name:lower() == target then match = name break end   -- case-insensitive
    end
    if not match then return "no '" .. profile .. "' profile" end
    local ok = pcall(db.SetProfile, db, match)
    return ok and ("loaded '" .. match .. "'") or "error"
end

-- Set ElvUI, Details and Bartender4 to the "default" profile, then reload.
-- Chat output survives /reload, so the per-addon results stay visible.
function ns.LoadDefaultProfiles()
    local any = false

    if ElvUI and ElvUI[1] then
        any = true
        ns.Print("ElvUI: " .. SetAceProfile(ElvUI[1].data, PROFILE_NAME))
    end

    if Bartender4 then
        any = true
        ns.Print("Bartender4: " .. SetAceProfile(Bartender4.db, PROFILE_NAME))
    end

    if Details then
        any = true
        local status
        local ok = pcall(function()
            local list = Details.GetProfileList and Details:GetProfileList()
            local match
            if list then
                for k, v in pairs(list) do
                    local candidate = type(v) == "string" and v or k
                    if type(candidate) == "string" and candidate:lower() == PROFILE_NAME:lower() then
                        match = candidate break   -- case-insensitive
                    end
                end
            end
            if Details.ApplyProfile and (match or not list) then
                Details:ApplyProfile(match or PROFILE_NAME)
                status = match and ("loaded '" .. match .. "'") or "loaded"
            elseif Details.db then
                status = SetAceProfile(Details.db, PROFILE_NAME)
            else
                status = "no profile API"
            end
        end)
        ns.Print("Details: " .. (ok and (status or "loaded") or "error"))
    end

    if not any then
        ns.Print("No supported addons found (ElvUI / Details / Bartender4).")
        return
    end

    ns.Print("Reloading UI...")
    ReloadUI()
end

-- The Overview tab of the settings window. Per-module enable switches live in the
-- window's rail now, so this page carries what is genuinely suite-wide: the bulk
-- scope controls, the UI profile helper, and a directory of what each module does.
function ns.BuildOverviewPage(page)
    local version = (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or ns.version

    page:Text("A suite of quality-of-life utilities for Project Ascension. "
        .. "Pick a module on the left to configure it; use the switch beside its name to "
        .. "turn it on or off.")

    page:Header("Settings scope")
    page:Text("Each module stores its settings account-wide (shared by all your characters) or "
        .. "per-character. Change one module's scope on its own page, or set them all at once here. "
        .. "Scope changes apply after a UI reload.")
    page:Row({
        {
            text = "All shared", width = 150,
            tooltip = "Every module reads the account-wide settings.",
            onClick = function()
                for _, m in ipairs(ns.modules) do
                    if m.key then ns.SetScope(m.key, "account") end
                end
                ns.MarkReloadNeeded("Settings scope changed for every module -- reload to apply it.")
            end,
        },
        {
            text = "All per-character", width = 150,
            tooltip = "Every module keeps its own settings for this character, seeded from the "
                .. "account settings.",
            onClick = function()
                for _, m in ipairs(ns.modules) do
                    if m.key then ns.SetScope(m.key, "character") end
                end
                ns.MarkReloadNeeded("Settings scope changed for every module -- reload to apply it.")
            end,
        },
    })

    page:Header("UI profiles")
    page:Button({
        text = "Load \"default\" profiles + reload", width = 240,
        onClick = ns.LoadDefaultProfiles,
    })
    page:Hint("Sets ElvUI, Details and Bartender4 to their \"default\" profile, then reloads. "
        .. "A profile that doesn't exist is left alone rather than created empty.")

    page:Header("Modules")
    for _, m in ipairs(ns.modules) do
        if m.key and m.title then
            local title = page:Text(m.title)
            title:SetTextColor(0.88, 0.88, 0.90)
            page.y = page.y + 4                      -- pull the description up under its title
            page:Hint(m.desc or "", 1)
        end
    end

    page:Spacer(4)
    page:Hint("HKSuite v" .. version .. "  --  /hk opens this window.")
end

-- HKSuite's settings are its own window, but the addon should still be reachable
-- the usual way, so Interface -> AddOns keeps a one-button page that opens it.
function ns.BuildOptionsStub()
    local panel = CreateFrame("Frame")
    panel.name = "HKSuite"
    ns.overviewPanel = panel

    local version = (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or ns.version

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HKSuite  |cff808080v" .. version .. "|r")

    local blurb = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetWidth(520)
    blurb:SetJustifyH("LEFT")
    blurb:SetText("HKSuite has its own settings window. Open it with the button below, or type |cffffd100/hk|r.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(200, 24)
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)
    open:SetText("Open HKSuite settings")
    open:SetScript("OnClick", function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            InterfaceOptionsFrame:Hide()
        end
        if GameMenuFrame and GameMenuFrame:IsShown() then GameMenuFrame:Hide() end
        ns.OpenSettings()
    end)

    InterfaceOptions_AddCategory(panel)
end
