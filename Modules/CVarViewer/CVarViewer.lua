local _, DF = ...

DF.ModuleSystem:Register("CVarViewer", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local viewer = {}
    local allCvars = nil       -- cached scan result
    local selectedCvar = nil   -- currently selected CVar name
    local modifiedOnly = false

    -- Forward declarations for functions referenced before definition
    local RefreshSidebar, ShowCVarDetail, ApplyCurrentValue, ResetCurrentCVar

    ---------------------------------------------------------------------------
    -- Sidebar: search box + modified toggle + TreeView
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    -- Search box
    local searchBox = DF.Widgets:CreateSearchBox(sidebarFrame, "Filter CVars...", 24)
    searchBox.frame:SetPoint("TOPLEFT", 4, -4)
    searchBox.frame:SetPoint("TOPRIGHT", -4, -4)

    -- Modified Only toggle button
    local toggleBtn = DF.Widgets:CreateButton(sidebarFrame, "Modified Only", 100, 20)
    toggleBtn:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", 0, -4)

    local toggleActive = false
    local toggleAccent = toggleBtn:CreateTexture(nil, "OVERLAY")
    toggleAccent:SetSize(toggleBtn:GetWidth(), 2)
    toggleAccent:SetPoint("BOTTOM", 0, 1)
    toggleAccent:SetColorTexture(unpack(DF.Colors.activityActive))
    toggleAccent:Hide()

    toggleBtn:SetScript("OnClick", function()
        toggleActive = not toggleActive
        modifiedOnly = toggleActive
        if toggleActive then
            toggleAccent:Show()
        else
            toggleAccent:Hide()
        end
        RefreshSidebar()
    end)

    -- TreeView below toggle
    local sidebarTree = DF.Widgets:CreateTreeView(sidebarFrame)
    sidebarTree.frame:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", -4, -4)
    sidebarTree.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + property grid + status
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 8)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    -- CVar name label in toolbar
    local nameLabel = toolbar:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFontObject(DF.Theme:CodeFont())
    nameLabel:SetPoint("LEFT", 6, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetTextColor(0.83, 0.83, 0.83, 1)
    nameLabel:SetText("")

    -- Right-side toolbar buttons
    local resetAllBtn = DF.Widgets:CreateButton(toolbar, "Reset All to Defaults", 140)
    resetAllBtn:SetPoint("RIGHT", -4, 0)

    -- Warning banner
    local banner = CreateFrame("Frame", nil, editorFrame, "BackdropTemplate")
    banner:SetHeight(20)
    banner:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    banner:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)
    local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints()
    bannerBg:SetColorTexture(0.35, 0.25, 0.05, 0.6)
    local bannerText = banner:CreateFontString(nil, "OVERLAY")
    bannerText:SetFontObject(DF.Theme:UIFont())
    bannerText:SetPoint("LEFT", 6, 0)
    bannerText:SetPoint("RIGHT", -6, 0)
    bannerText:SetJustifyH("LEFT")
    bannerText:SetTextColor(0.9, 0.75, 0.3, 1)
    bannerText:SetText("Changing CVars may affect performance or stability. Some are protected or reset on logout.")

    -- Property grid for CVar detail
    local grid = DF.Widgets:CreatePropertyGrid(editorFrame)
    grid.frame:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -2)
    grid.frame:SetPoint("BOTTOMRIGHT", 0, 24)

    -- Status line at the bottom
    local statusFrame = CreateFrame("Frame", nil, editorFrame)
    statusFrame:SetHeight(20)
    statusFrame:SetPoint("BOTTOMLEFT", 0, 0)
    statusFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local statusBg = statusFrame:CreateTexture(nil, "BACKGROUND")
    statusBg:SetAllPoints()
    statusBg:SetColorTexture(0.10, 0.10, 0.12, 1)

    local statusText = statusFrame:CreateFontString(nil, "OVERLAY")
    statusText:SetFontObject(DF.Theme:UIFont())
    statusText:SetPoint("LEFT", 6, 0)
    statusText:SetPoint("RIGHT", -6, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(0.6, 0.6, 0.6, 1)
    statusText:SetText("")

    local function SetStatus(text)
        statusText:SetText(text or "")
    end

    ---------------------------------------------------------------------------
    -- Inline editing state
    ---------------------------------------------------------------------------
    local editBox = nil
    local setBtn = nil
    local resetBtn = nil

    -- Create the inline edit box (reused across selections)
    local function GetEditBox()
        if editBox then return editBox end

        editBox = CreateFrame("EditBox", nil, grid.pane:GetContent(), "BackdropTemplate")
        editBox:SetHeight(DF.Layout.rowHeight)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(500)
        DF.Theme:ApplyInputStyle(editBox)
        editBox:Hide()

        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            ApplyCurrentValue()
        end)

        return editBox
    end

    local function GetSetButton()
        if setBtn then return setBtn end
        setBtn = DF.Widgets:CreateButton(grid.pane:GetContent(), "Set", 40, DF.Layout.rowHeight)
        setBtn:Hide()
        setBtn:SetScript("OnClick", function()
            ApplyCurrentValue()
        end)
        return setBtn
    end

    local function GetResetButton()
        if resetBtn then return resetBtn end
        resetBtn = DF.Widgets:CreateButton(grid.pane:GetContent(), "Reset", 50, DF.Layout.rowHeight)
        resetBtn:Hide()
        resetBtn:SetScript("OnClick", function()
            ResetCurrentCVar()
        end)
        return resetBtn
    end

    ---------------------------------------------------------------------------
    -- Apply / Reset logic
    ---------------------------------------------------------------------------
    ApplyCurrentValue = function()
        if not selectedCvar then return end
        local eb = GetEditBox()
        local newVal = eb:GetText()

        local success, err = DF.CVarData:SetValue(selectedCvar, newVal)
        if success then
            SetStatus(DF.Colors.comment .. "Set " .. selectedCvar .. " = " .. newVal .. "|r")
            ShowCVarDetail(selectedCvar)
            RefreshSidebar()
        else
            SetStatus(DF.Colors.error .. "Error: " .. (err or "unknown error") .. "|r")
        end
    end

    ResetCurrentCVar = function()
        if not selectedCvar then return end

        local success, err = DF.CVarData:ResetToDefault(selectedCvar)
        if success then
            SetStatus(DF.Colors.comment .. "Reset " .. selectedCvar .. " to default|r")
            ShowCVarDetail(selectedCvar)
            RefreshSidebar()
        else
            SetStatus(DF.Colors.error .. "Error: " .. (err or "unknown error") .. "|r")
        end
    end

    ---------------------------------------------------------------------------
    -- Show CVar detail in editor
    ---------------------------------------------------------------------------
    ShowCVarDetail = function(name)
        selectedCvar = name
        local info = DF.CVarData:GetInfo(name)
        if not info then
            nameLabel:SetText("")
            grid:Clear()
            return
        end

        nameLabel:SetText(DF.Colors.func .. info.name .. "|r")

        -- Build sections for the property grid
        -- We use the grid for the Info and Actions sections,
        -- but the Value section needs the inline edit box.
        local sections = {
            {
                title = "Value",
                props = {
                    -- Current row is a placeholder; we overlay the EditBox on it
                    { key = "Current", value = tostring(info.value or "") },
                    { key = "Default", value = tostring(info.default or "") },
                    { key = "Type", value = info.type .. " (inferred)" },
                },
            },
            {
                title = "Info",
                props = {
                    { key = "Description", value = info.help ~= "" and info.help or DF.Colors.dim .. "(none)|r" },
                    { key = "Category", value = info.categoryName },
                    { key = "Read-Only", value = info.readOnly and "Yes" or "No" },
                    { key = "Per-Char", value = info.perChar and "Yes" or "No" },
                },
            },
            {
                title = "Actions",
                props = {
                    { key = "Copy Name", value = DF.Colors.func .. "[Click to Copy]|r", onClick = function()
                        DF.Widgets:ShowCopyDialog(info.name)
                    end },
                    { key = "Copy /run", value = DF.Colors.func .. "[Click to Copy]|r", onClick = function()
                        local cmd = '/run SetCVar("' .. info.name .. '", "' .. tostring(info.value or "") .. '")'
                        DF.Widgets:ShowCopyDialog(cmd)
                    end },
                },
            },
        }

        grid:SetSections(sections)

        -- Overlay the EditBox and Set/Reset buttons on the Current value row
        -- The "Current" row is row index 2 (1 = section header, 2 = first prop)
        C_Timer.After(0, function()
            local eb = GetEditBox()
            local sb = GetSetButton()
            local rb = GetResetButton()
            local row = grid.rows[2]
            if row then
                -- Hide the default value text on the Current row
                row.value:SetText("")

                eb:ClearAllPoints()
                eb:SetPoint("LEFT", row, "LEFT", DF.Layout.propertyLabelW + 4, 0)
                eb:SetPoint("RIGHT", sb, "LEFT", -4, 0)
                eb:SetHeight(DF.Layout.rowHeight)
                eb:SetText(tostring(info.value or ""))
                eb:Show()

                sb:ClearAllPoints()
                sb:SetPoint("RIGHT", rb, "LEFT", -2, 0)
                sb:Show()

                rb:ClearAllPoints()
                rb:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                rb:Show()
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Sidebar refresh
    ---------------------------------------------------------------------------
    RefreshSidebar = function()
        if not allCvars then return end

        local filter = searchBox:GetText()
        local nodes = DF.CVarData:BuildSidebarNodes(allCvars, filter, modifiedOnly)
        sidebarTree:SetNodes(nodes)
    end

    -- Wire search
    searchBox:SetOnSearch(function()
        RefreshSidebar()
    end)

    -- Wire sidebar selection
    sidebarTree:SetOnSelect(function(node)
        if node and node.data and node.data.name then
            ShowCVarDetail(node.data.name)
        end
    end)

    ---------------------------------------------------------------------------
    -- Reset All to Defaults
    ---------------------------------------------------------------------------
    StaticPopupDialogs["DEVFORGE_CVAR_RESET_ALL"] = {
        text = "Reset ALL modified CVars to their default values?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if not allCvars then return end
            local count = 0
            for _, cmd in ipairs(allCvars) do
                local name = cmd.command
                local okV, val = pcall(C_CVar.GetCVar, name)
                local okD, def = pcall(C_CVar.GetCVarDefault, name)
                if okV and okD and val and def and tostring(val) ~= tostring(def) then
                    local ok = pcall(C_CVar.SetCVar, name, def)
                    if ok then
                        count = count + 1
                    end
                end
            end
            SetStatus(DF.Colors.comment .. "Reset " .. count .. " CVar(s) to defaults|r")
            RefreshSidebar()
            if selectedCvar then
                ShowCVarDetail(selectedCvar)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    resetAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("DEVFORGE_CVAR_RESET_ALL")
    end)

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function viewer:OnFirstActivate()
        local cvars, err = DF.CVarData:ScanAll()
        if cvars then
            allCvars = cvars
            DF.CVarData:BuildLookup(allCvars)
            RefreshSidebar()
        else
            -- Show empty state
            sidebarTree:SetNodes({
                { id = "empty", text = DF.Colors.dim .. (err or "No CVars available") .. "|r" },
            })
        end
    end

    function viewer:OnActivate()
        -- Refresh displayed CVar (values may have changed externally)
        if selectedCvar then
            ShowCVarDetail(selectedCvar)
        end
    end

    viewer.sidebar = sidebarFrame
    viewer.editor = editorFrame
    return viewer
end, "CVars")
