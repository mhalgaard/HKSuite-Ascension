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
    local ROW_H     = 30      -- height of each module row
    local LIST_W    = 470     -- width of the list container
    local SHARED_X  = 348     -- x-offset of the Shared checkbox within a row

    local panel = CreateFrame("Frame")
    panel.name = "HKSuite"
    ns.overviewPanel = panel

    local version = (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or ns.version

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HKSuite  |cff808080v" .. version .. "|r")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Enable or disable each module. |cffffd100Shared|r = account-wide settings; uncheck for this character's own settings.")

    -- Collect the modules we actually render (those with a key + title).
    local mods = {}
    for _, m in ipairs(ns.modules) do
        if m.key and m.title then mods[#mods + 1] = m end
    end

    -- ---- Column headers -------------------------------------------------
    local hdrModule = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hdrModule:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 8, -16)
    hdrModule:SetText("|cffffd100Module|r")

    local hdrShared = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hdrShared:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", SHARED_X + 8, -16)
    hdrShared:SetText("|cffffd100Shared|r")

    -- ---- List container -------------------------------------------------
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", hdrModule, "BOTTOMLEFT", -8, -6)
    list:SetSize(LIST_W, #mods * ROW_H + 8)
    list:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    list:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
    list:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local enableChecks, scopeChecks = {}, {}
    local function RefreshChecks()
        for key, cb in pairs(enableChecks) do cb:SetChecked(ns.IsModuleEnabled(key)) end
        for key, cb in pairs(scopeChecks) do cb:SetChecked(ns.GetScope(key) == "account") end
    end

    local SCOPE_TIP = "Checked: this module uses shared account-wide settings.\nUnchecked: this character uses its own settings for this module (seeded from the account settings).\nApplies after a reload."

    for idx, module in ipairs(mods) do
        local key = module.key

        local row = CreateFrame("Button", nil, list)
        row:SetSize(LIST_W - 8, ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (idx - 1) * ROW_H)

        -- Alternating stripe for readability.
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if idx % 2 == 0 then bg:SetVertexColor(1, 1, 1, 0.035) else bg:SetVertexColor(0, 0, 0, 0) end

        -- Gold hover highlight.
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.10)

        local cb = ns.CreateCheck(row, module.title, module.desc, ns.IsModuleEnabled(key))
        cb:SetPoint("LEFT", row, "LEFT", 4, 0)
        cb:SetScript("OnClick", function(self)
            ns.SetModuleEnabled(key, self:GetChecked() and true or false)
        end)
        enableChecks[key] = cb

        -- Scope toggle (no per-row label; the column header covers it).
        local sc = ns.CreateCheck(row, "", SCOPE_TIP, ns.GetScope(key) == "account")
        sc:SetPoint("LEFT", row, "LEFT", SHARED_X, 0)
        sc:SetScript("OnClick", function(self)
            ns.SetScope(key, self:GetChecked() and "account" or "character")
            enableChecks[key]:SetChecked(ns.IsModuleEnabled(key))
            ns.PromptReload()
        end)
        scopeChecks[key] = sc

        -- Clicking anywhere on the row toggles the module enable.
        row:SetScript("OnClick", function()
            local newv = not cb:GetChecked()
            cb:SetChecked(newv)
            ns.SetModuleEnabled(key, newv and true or false)
        end)
    end

    -- ---- Bulk scope buttons --------------------------------------------
    local allShared = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    allShared:SetSize(150, 22)
    allShared:SetText("All shared")
    allShared:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -14)
    allShared:SetScript("OnClick", function()
        for _, m in ipairs(ns.modules) do if m.key then ns.SetScope(m.key, "account") end end
        RefreshChecks()
        ns.PromptReload()
    end)

    local allChar = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    allChar:SetSize(150, 22)
    allChar:SetText("All per-character")
    allChar:SetPoint("LEFT", allShared, "RIGHT", 8, 0)
    allChar:SetScript("OnClick", function()
        for _, m in ipairs(ns.modules) do if m.key then ns.SetScope(m.key, "character") end end
        RefreshChecks()
        ns.PromptReload()
    end)

    -- ---- Divider + UI Profiles -----------------------------------------
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(1, 1, 1, 0.12)
    divider:SetSize(LIST_W, 1)
    divider:SetPoint("TOPLEFT", allShared, "BOTTOMLEFT", 0, -16)

    local sep = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sep:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
    sep:SetText("|cffffd100UI Profiles|r")

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
