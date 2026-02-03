local _, DF = ...

-- CPU profiling reload dialogs
StaticPopupDialogs["DEVFORGE_ENABLE_PROFILING"] = {
    text = "CPU profiling requires a UI reload. Enable and reload now?",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function()
        SetCVar("scriptProfile", 1)
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["DEVFORGE_DISABLE_PROFILING"] = {
    text = "Disabling CPU profiling requires a UI reload. Disable and reload now?",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function()
        SetCVar("scriptProfile", 0)
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Register the Performance Monitor module (no sidebar, full editor)
DF.ModuleSystem:Register("Performance", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local monitor = {}

    -- Full editor frame (no sidebar for Performance)
    local frame = CreateFrame("Frame", nil, editorParent)
    frame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local refreshBtn = DF.Widgets:CreateButton(toolbar, "Refresh", 65)
    refreshBtn:SetPoint("LEFT", 2, 0)

    local resetBtn = DF.Widgets:CreateButton(toolbar, "Reset", 55)
    resetBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 4, 0)

    local cpuBtn = DF.Widgets:CreateButton(toolbar, "Enable CPU", 90)
    cpuBtn:SetPoint("LEFT", resetBtn, "RIGHT", 4, 0)

    local intervalLabel = toolbar:CreateFontString(nil, "OVERLAY")
    intervalLabel:SetFontObject(DF.Theme:UIFont())
    intervalLabel:SetPoint("LEFT", cpuBtn, "RIGHT", 12, 0)
    intervalLabel:SetTextColor(0.55, 0.55, 0.55, 1)
    intervalLabel:SetText("Poll:")

    local intervals = { 1, 2, 5, 10 }
    local intervalBtns = {}
    local prevAnchor = intervalLabel
    for _, sec in ipairs(intervals) do
        local btn = DF.Widgets:CreateButton(toolbar, sec .. "s", 30)
        btn:SetPoint("LEFT", prevAnchor, "RIGHT", 3, 0)
        btn.interval = sec
        btn:SetScript("OnClick", function()
            DF.PerfData:SetPollingInterval(sec)
            for _, ib in ipairs(intervalBtns) do
                if ib.interval == sec then ib:SetAlpha(1) else ib:SetAlpha(0.5) end
            end
        end)
        intervalBtns[#intervalBtns + 1] = btn
        prevAnchor = btn
    end

    local function HighlightCurrentInterval()
        local current = DF.PerfData:GetPollingInterval()
        for _, ib in ipairs(intervalBtns) do
            if ib.interval == current then ib:SetAlpha(1) else ib:SetAlpha(0.5) end
        end
    end

    local totalLabel = toolbar:CreateFontString(nil, "OVERLAY")
    totalLabel:SetFontObject(DF.Theme:UIFont())
    totalLabel:SetPoint("RIGHT", -4, 0)
    totalLabel:SetTextColor(0.6, 0.7, 0.85, 1)

    local function UpdateTotalLabel()
        local totalKB = DF.PerfData:GetTotalMemory()
        if totalKB >= 1024 then
            totalLabel:SetText(format("Total: %.1f MB", totalKB / 1024))
        else
            totalLabel:SetText(format("Total: %.0f KB", totalKB))
        end
    end

    local function UpdateCpuButton()
        if DF.PerfData:IsProfilingEnabled() then
            cpuBtn:SetLabel("Disable CPU")
        else
            cpuBtn:SetLabel("Enable CPU")
        end
    end

    local searchRow = CreateFrame("Frame", nil, frame)
    searchRow:SetHeight(22)
    searchRow:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -1)
    searchRow:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -1)

    local searchBox = DF.Widgets:CreateSearchBox(searchRow, "Filter addons...")
    searchBox.frame:SetPoint("LEFT", 2, 0)
    searchBox.frame:SetPoint("RIGHT", -2, 0)
    searchBox.frame:SetHeight(20)

    local perfTable = DF.PerfTable:Create(frame)
    perfTable.frame:SetPoint("TOPLEFT", searchRow, "BOTTOMLEFT", 0, -1)
    perfTable.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    searchBox:SetOnSearch(function(text)
        perfTable:SetSearchFilter(text)
    end)

    DF.PerfData:SetOnUpdate(function()
        perfTable:SortAndUpdate()
        UpdateTotalLabel()
    end)

    refreshBtn:SetScript("OnClick", function() DF.PerfData:ForceUpdate() end)
    resetBtn:SetScript("OnClick", function() DF.PerfData:Reset() end)

    cpuBtn:SetScript("OnClick", function()
        if DF.PerfData:IsProfilingEnabled() then
            StaticPopup_Show("DEVFORGE_DISABLE_PROFILING")
        else
            StaticPopup_Show("DEVFORGE_ENABLE_PROFILING")
        end
    end)

    function monitor:OnFirstActivate()
        DF.PerfData:Init()
        DF.PerfData:StartPolling()
        perfTable:SortAndUpdate()
        UpdateTotalLabel()
        UpdateCpuButton()
        HighlightCurrentInterval()
    end

    function monitor:OnActivate()
        DF.PerfData:StartPolling()
        perfTable:SortAndUpdate()
        UpdateTotalLabel()
        UpdateCpuButton()
        HighlightCurrentInterval()
    end

    function monitor:OnDeactivate()
        DF.PerfData:StopPolling()
    end

    -- Legacy single-frame module (no sidebar)
    monitor.frame = frame
    return monitor
end, "Perf")
