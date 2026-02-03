local _, DF = ...

-- Capture frame for event recording
local captureFrame = CreateFrame("Frame")
local capturing = false

-- Register the Event Monitor module with sidebar + editor split
DF.ModuleSystem:Register("EventMonitor", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local monitor = {}

    -- Initialize log
    DF.EventMonitorLog:Init()

    ---------------------------------------------------------------------------
    -- Sidebar: event reference tree + filter (browse mode) / filter bar (live mode)
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    -- Two-mode sidebar: "live" shows filter controls, "browse" shows event reference tree
    local sidebarMode = "live" -- "live" | "browse"

    -- Live filter panel
    local liveFilterPanel = CreateFrame("Frame", nil, sidebarFrame)
    liveFilterPanel:SetAllPoints(sidebarFrame)

    local searchBox = DF.Widgets:CreateSearchBox(liveFilterPanel, "Filter events...", 24)
    searchBox.frame:SetPoint("TOPLEFT", 2, 0)
    searchBox.frame:SetPoint("TOPRIGHT", -2, 0)

    local filterInfoLabel = liveFilterPanel:CreateFontString(nil, "OVERLAY")
    filterInfoLabel:SetFontObject(DF.Theme:UIFont())
    filterInfoLabel:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", 4, -6)
    filterInfoLabel:SetPoint("TOPRIGHT", searchBox.frame, "BOTTOMRIGHT", -4, -6)
    filterInfoLabel:SetJustifyH("LEFT")
    filterInfoLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    filterInfoLabel:SetText("Type to filter live events.\nUse Browse to search all known events.")

    -- Browse panel (event reference tree)
    local browsePanel = CreateFrame("Frame", nil, sidebarFrame)
    browsePanel:SetAllPoints(sidebarFrame)
    browsePanel:Hide()

    local browseSearch = DF.Widgets:CreateSearchBox(browsePanel, "Search events...", 24)
    browseSearch.frame:SetPoint("TOPLEFT", 0, 0)
    browseSearch.frame:SetPoint("TOPRIGHT", 0, 0)

    local browseTree = DF.Widgets:CreateTreeView(browsePanel)
    browseTree.frame:SetPoint("TOPLEFT", browseSearch.frame, "BOTTOMLEFT", 0, -2)
    browseTree.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + live log / detail view
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local startBtn = DF.Widgets:CreateButton(toolbar, "Start", 60)
    startBtn:SetPoint("LEFT", 2, 0)

    local pauseBtn = DF.Widgets:CreateButton(toolbar, "Pause", 60)
    pauseBtn:SetPoint("LEFT", startBtn, "RIGHT", 4, 0)

    local clearBtn = DF.Widgets:CreateButton(toolbar, "Clear", 55)
    clearBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0)

    local filtersBtn = DF.Widgets:CreateButton(toolbar, "Filters", 60)
    filtersBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)

    local browseBtn = DF.Widgets:CreateButton(toolbar, "Browse", 65)
    browseBtn:SetPoint("LEFT", filtersBtn, "RIGHT", 4, 0)

    local insertHandlerBtn = DF.Widgets:CreateButton(toolbar, "Insert Handler", 100)
    insertHandlerBtn:SetPoint("LEFT", browseBtn, "RIGHT", 8, 0)
    insertHandlerBtn:Hide()

    local etraceBtn = DF.Widgets:CreateButton(toolbar, "Blizz Trace", 80)
    etraceBtn:SetPoint("RIGHT", -4, 0)
    etraceBtn:SetScript("OnClick", function()
        if ChatFrame_ImportAllListsToHash then ChatFrame_ImportAllListsToHash() end
        if hash_SlashCmdList and hash_SlashCmdList["/ETRACE"] then hash_SlashCmdList["/ETRACE"]("") end
    end)

    local countLabel = toolbar:CreateFontString(nil, "OVERLAY")
    countLabel:SetFontObject(DF.Theme:UIFont())
    countLabel:SetPoint("RIGHT", etraceBtn, "LEFT", -10, 0)
    countLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    countLabel:SetText("0 events")

    local statusLabel = toolbar:CreateFontString(nil, "OVERLAY")
    statusLabel:SetFontObject(DF.Theme:UIFont())
    statusLabel:SetPoint("RIGHT", countLabel, "LEFT", -10, 0)
    statusLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    statusLabel:SetText("Stopped")

    -- Live log output
    local livePanel = CreateFrame("Frame", nil, editorFrame)
    livePanel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -1)
    livePanel:SetPoint("BOTTOMRIGHT", 0, 0)

    local output = DF.ConsoleOutput:Create(livePanel)
    output.frame:SetAllPoints(livePanel)

    -- Browse detail panel
    local browseDetailPanel = CreateFrame("Frame", nil, editorFrame, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(browseDetailPanel, true)
    browseDetailPanel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -1)
    browseDetailPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    browseDetailPanel:Hide()

    local detailScroll = DF.Widgets:CreateScrollPane(browseDetailPanel, false)
    detailScroll.frame:SetPoint("TOPLEFT", 4, -4)
    detailScroll.frame:SetPoint("BOTTOMRIGHT", -4, 4)

    local detailText = CreateFrame("EditBox", nil, detailScroll:GetContent())
    detailText:SetPoint("TOPLEFT", 6, -6)
    detailText:SetPoint("RIGHT", -6, 0)
    detailText:SetMultiLine(true)
    detailText:SetAutoFocus(false)
    detailText:SetFontObject(DF.Theme:CodeFont())
    detailText:SetTextColor(0.83, 0.83, 0.83, 1)
    detailText:EnableKeyboard(false)
    detailText:SetScript("OnChar", function() end)
    detailText:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    detailText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Filter panel
    local filterPanel = DF.EventMonitorFilter:Create(editorFrame)
    filterPanel.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -1)
    filterPanel.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    filterPanel.frame:Hide()

    local blacklistDirty = false
    filterPanel:SetOnChanged(function() blacklistDirty = true end)

    ---------------------------------------------------------------------------
    -- Capture start/stop
    ---------------------------------------------------------------------------
    local function StartCapture()
        if capturing then return end
        capturing = true
        captureFrame:SetScript("OnEvent", function(_, event, ...)
            local captured = DF.EventMonitorLog:Push(event, GetTime(), ...)
            -- Only fire for bottom panel if the event passed all filters
            if captured then
                DF.EventBus:Fire("DF_EVENT_CAPTURED", event, GetTime())
            end
        end)
        captureFrame:RegisterAllEvents()
        statusLabel:SetText(DF.Colors.boolTrue .. "Recording|r")
        startBtn:SetLabel("Stop")
    end

    local function StopCapture()
        if not capturing then return end
        capturing = false
        captureFrame:UnregisterAllEvents()
        captureFrame:SetScript("OnEvent", nil)
        statusLabel:SetText(DF.Colors.dim .. "Stopped|r")
        startBtn:SetLabel("Start")
    end

    ---------------------------------------------------------------------------
    -- View toggle
    ---------------------------------------------------------------------------
    local activeView = "live"
    local searchFilter = ""
    local browseTreeBuilt = false
    local selectedRefEvent = nil

    local RebuildOutput
    local ShowView

    local function UpdateCount()
        countLabel:SetText(DF.EventMonitorLog:GetCount() .. " events")
    end

    local function PassesFilter(entry)
        if searchFilter == "" then return true end
        return entry.event:lower():find(searchFilter, 1, true) ~= nil
    end

    RebuildOutput = function()
        output:Clear()
        local entries = DF.EventMonitorLog:GetEntries()
        local lines = {}
        for _, entry in ipairs(entries) do
            if PassesFilter(entry) then
                lines[#lines + 1] = DF.EventMonitorLog:FormatEntry(entry)
            end
        end
        if #lines > 0 then output:AddLines(lines) end
        UpdateCount()
    end

    ShowView = function(view)
        local leavingFilters = (activeView == "filters" and view ~= "filters")
        activeView = view

        livePanel:Hide()
        filterPanel.frame:Hide()
        browseDetailPanel:Hide()

        -- Sidebar mode
        liveFilterPanel:Hide()
        browsePanel:Hide()

        if view == "live" then
            livePanel:Show()
            liveFilterPanel:Show()
            browseBtn:SetLabel("Browse")
            insertHandlerBtn:Hide()
            sidebarMode = "live"
        elseif view == "filters" then
            filterPanel:Refresh()
            filterPanel.frame:Show()
            liveFilterPanel:Show()
            browseBtn:SetLabel("Browse")
            insertHandlerBtn:Hide()
            sidebarMode = "live"
        elseif view == "browse" then
            browseDetailPanel:Show()
            browsePanel:Show()
            browseBtn:SetLabel("Live Log")
            sidebarMode = "browse"
        end

        if leavingFilters and blacklistDirty then
            blacklistDirty = false
            RebuildOutput()
        end
    end

    ---------------------------------------------------------------------------
    -- Event detail (for browse mode)
    ---------------------------------------------------------------------------
    local function ShowEventDetail(entry)
        if not entry or not entry.event then
            detailText:SetText(DF.Colors.dim .. "Select an event from the list.|r")
            insertHandlerBtn:Hide()
            selectedRefEvent = nil
            C_Timer.After(0, function()
                detailScroll:SetContentHeight(detailText:GetHeight() + 20)
            end)
            return
        end

        selectedRefEvent = entry.event

        local lines = {}
        lines[#lines + 1] = DF.Colors.keyword .. entry.event .. "|r"
        lines[#lines + 1] = DF.Colors.dim .. "Category: " .. (entry.category or "?") .. "|r"
        lines[#lines + 1] = ""
        lines[#lines + 1] = DF.Colors.text .. entry.desc .. "|r"
        lines[#lines + 1] = ""

        lines[#lines + 1] = DF.Colors.comment .. "-- Usage:|r"
        lines[#lines + 1] = DF.Colors.text .. 'local f = CreateFrame("Frame")|r'
        lines[#lines + 1] = DF.Colors.text .. 'f:RegisterEvent("' .. entry.event .. '")|r'
        lines[#lines + 1] = DF.Colors.text .. "f:SetScript(\"OnEvent\", function(self, event, ...)|r"
        lines[#lines + 1] = DF.Colors.text .. "    -- handle event|r"
        lines[#lines + 1] = DF.Colors.text .. "end)|r"
        lines[#lines + 1] = ""

        if DF.APIBrowserData and DF.APIBrowserData:IsLoaded() then
            local allEntries = DF.APIBrowserData:GetAllEntries()
            for _, apiEntry in ipairs(allEntries) do
                if apiEntry.type == "event" and apiEntry.name == entry.event then
                    lines[#lines + 1] = DF.Colors.func .. "API Documentation:|r"
                    if apiEntry.doc and apiEntry.doc.Payload and #apiEntry.doc.Payload > 0 then
                        lines[#lines + 1] = DF.Colors.keyword .. "Payload:|r"
                        for _, arg in ipairs(apiEntry.doc.Payload) do
                            local nilable = arg.Nilable and (DF.Colors.dim .. " [nilable]|r") or ""
                            lines[#lines + 1] = "  " .. DF.Colors.text .. (arg.Name or "?") .. "|r"
                                .. " : " .. DF.Colors.tableRef .. (arg.Type or "any") .. "|r" .. nilable
                        end
                    end
                    if apiEntry.doc and apiEntry.doc.Documentation then
                        lines[#lines + 1] = ""
                        lines[#lines + 1] = DF.Colors.comment .. "-- " .. apiEntry.doc.Documentation .. "|r"
                    end
                    break
                end
            end
        end

        detailText:SetText(table.concat(lines, "\n"))
        insertHandlerBtn:Show()

        C_Timer.After(0, function()
            local w = detailScroll:GetContent():GetWidth()
            detailText:SetWidth(w - 12)
            detailScroll:SetContentHeight(detailText:GetHeight() + 40)
            detailScroll:ScrollToTop()
        end)
    end

    browseDetailPanel:SetScript("OnSizeChanged", function()
        local w = detailScroll:GetContent():GetWidth()
        detailScroll:GetContent():SetWidth(detailScroll.scrollFrame:GetWidth())
        detailText:SetWidth(math.max(100, w - 12))
        C_Timer.After(0, function()
            detailScroll:SetContentHeight(detailText:GetHeight() + 40)
            detailScroll:UpdateThumb()
        end)
    end)

    -- Build browse tree
    local function RefreshBrowseTree(query)
        local ok, nodes = pcall(DF.EventIndex.BuildTreeNodes, DF.EventIndex, query)
        if ok and nodes then
            browseTree:SetNodes(nodes)
            if query and query ~= "" then browseTree:ExpandAll() end
            browseTreeBuilt = true
        end
    end

    browseSearch:SetOnSearch(function(query) RefreshBrowseTree(query) end)

    browseTree:SetOnSelect(function(node)
        if node and node.data and node.data.event then
            ShowEventDetail(node.data)
        elseif node and node.data and node.data.category then
            local cat = node.data.category
            local count = 0
            for _, c in ipairs(DF.EventIndex:GetCategories()) do
                if c.name == cat then count = #c.events; break end
            end
            detailText:SetText(
                DF.Colors.func .. cat .. "|r\n\n" ..
                DF.Colors.text .. count .. " events in this category.|r\n\n" ..
                DF.Colors.dim .. "Click an event to see details.|r"
            )
            insertHandlerBtn:Hide()
            selectedRefEvent = nil
        end
    end)

    ---------------------------------------------------------------------------
    -- Insert Handler button: generates event handler code
    ---------------------------------------------------------------------------
    insertHandlerBtn:SetScript("OnClick", function()
        if not selectedRefEvent then return end
        local code = 'local f = CreateFrame("Frame")\n'
            .. 'f:RegisterEvent("' .. selectedRefEvent .. '")\n'
            .. 'f:SetScript("OnEvent", function(self, event, ...)\n'
            .. '    -- handle ' .. selectedRefEvent .. '\n'
            .. 'end)'
        DF.EventBus:Fire("DF_INSERT_TO_EDITOR", { text = code })
    end)

    -- "Monitor This" in browse mode
    local monitorBtn = DF.Widgets:CreateButton(browseDetailPanel, "Monitor This", 100, 20)
    monitorBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    monitorBtn:Hide()

    monitorBtn:SetScript("OnClick", function()
        if not selectedRefEvent then return end
        local eventToMonitor = selectedRefEvent
        ShowView("live")
        if not capturing then StartCapture() end
        DF.EventMonitorLog:ClearFilters()
        DF.EventMonitorLog:SetFilter(eventToMonitor, true)
        output:AddLine(DF.Colors.func .. "Now monitoring: " .. DF.Colors.keyword .. eventToMonitor .. "|r")
    end)

    ShowEventDetail(nil)

    ---------------------------------------------------------------------------
    -- Wire up buttons
    ---------------------------------------------------------------------------
    filtersBtn:SetScript("OnClick", function()
        if activeView == "filters" then ShowView("live") else ShowView("filters") end
    end)

    browseBtn:SetScript("OnClick", function()
        if activeView == "browse" then ShowView("live") else ShowView("browse") end
    end)

    DF.EventMonitorLog:SetOnNewEntry(function(entry)
        if PassesFilter(entry) then
            output:AddLine(DF.EventMonitorLog:FormatEntry(entry))
        end
        UpdateCount()
    end)

    searchBox:SetOnSearch(function(query)
        searchFilter = (query or ""):lower()
        RebuildOutput()
    end)

    startBtn:SetScript("OnClick", function()
        if capturing then
            StopCapture()
        else
            if activeView ~= "live" then ShowView("live") end
            DF.EventMonitorLog:ClearFilters()
            StartCapture()
        end
    end)

    pauseBtn:SetScript("OnClick", function()
        if DF.EventMonitorLog:IsPaused() then
            DF.EventMonitorLog:SetPaused(false)
            pauseBtn:SetLabel("Pause")
            statusLabel:SetText(DF.Colors.boolTrue .. "Recording|r")
        else
            DF.EventMonitorLog:SetPaused(true)
            pauseBtn:SetLabel("Resume")
            statusLabel:SetText(DF.Colors.string .. "Paused|r")
        end
    end)

    clearBtn:SetScript("OnClick", function()
        DF.EventMonitorLog:Clear()
        output:Clear()
        UpdateCount()
        DF.EventBus:Fire("DF_EVENTS_CLEARED")
    end)

    -- Welcome message
    output:AddLine(DF.Colors.func .. "Event Monitor|r")
    output:AddLine(DF.Colors.dim .. "Click Start to begin capturing WoW events.|r")
    output:AddLine(DF.Colors.dim .. 'Click Browse to search the event reference (' .. DF.EventIndex:GetCount() .. ' known events).|r')
    output:AddLine("")

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function monitor:OnActivate()
        if not browseTreeBuilt then
            C_Timer.After(0, function() RefreshBrowseTree(nil) end)
        end
    end

    function monitor:OnDeactivate()
        -- Keep capturing in background if active
    end

    function monitor:RegisterEvent(event)
        if not capturing then StartCapture() end
    end

    monitor.sidebar = sidebarFrame
    monitor.editor = editorFrame
    return monitor
end, "Events")
