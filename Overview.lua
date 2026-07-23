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

-- Builds the top-level "HKSuite" page: a quick enable/disable toggle for every
-- registered module. Because it iterates ns.modules, any new module that
-- registers with a `key` and `title` shows up here automatically.
function ns.BuildOverview()
    local panel = CreateFrame("Frame")
    panel.name = "HKSuite"
    ns.overviewPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HKSuite  |cff808080v" .. ns.version .. "|r")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Modules — enable or disable each utility. Configure each one on its sub-page.")

    local anchor = subtitle
    for _, module in ipairs(ns.modules) do
        if module.key and module.title then
            local key = module.key
            local cb = ns.CreateCheck(panel, module.title, module.desc, ns.IsModuleEnabled(key))
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
            cb:SetScript("OnClick", function(self)
                ns.config.modules[key] = self:GetChecked() and true or false
            end)
            anchor = cb
        end
    end

    local sep = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sep:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -22)
    sep:SetText("UI Profiles")

    local btn = CreateFrame("Button", "HKSuiteLoadProfilesButton", panel, "UIPanelButtonTemplate")
    btn:SetSize(230, 24)
    btn:SetText("Load \"default\" profiles + reload")
    btn:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
    btn:SetScript("OnClick", ns.LoadDefaultProfiles)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -6)
    hint:SetText("Sets ElvUI, Details and Bartender4 to their \"default\" profile, then reloads.")

    InterfaceOptions_AddCategory(panel)
end
