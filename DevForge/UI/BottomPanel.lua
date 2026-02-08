local _, DF = ...

DF.UI = DF.UI or {}
DF.UI.BottomPanel = {}

local BottomPanel = DF.UI.BottomPanel

function BottomPanel:Create(parent)
    local L = DF.Layout

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    frame:SetBackdropColor(unpack(DF.Colors.bottomBg))

    local panel = {
        frame = frame,
        collapsed = false,
        height = L.bottomDefaultH,
        activeTab = "output",
        tabs = {},
        badges = { output = 0, errors = 0, events = 0 },
    }

    ---------------------------------------------------------------------------
    -- Tab bar (top strip of the bottom panel)
    ---------------------------------------------------------------------------
    local tabBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tabBar:SetHeight(L.bottomTabHeight)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", 0, 0)
    tabBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    tabBar:SetBackdropColor(unpack(DF.Colors.sidebarHeaderBg))
    panel.tabBar = tabBar

    -- Collapse toggle (left side of tab bar)
    local collapseBtn = CreateFrame("Button", nil, tabBar)
    collapseBtn:RegisterForClicks("LeftButtonUp")
    collapseBtn:SetSize(20, L.bottomTabHeight)
    collapseBtn:SetPoint("LEFT", 2, 0)

    local collapseTex = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseTex:SetSize(10, 10)
    collapseTex:SetPoint("CENTER", 0, 0)
    collapseTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    collapseTex:SetRotation(math.pi / 2) -- rotate to point up
    collapseTex:SetVertexColor(0.6, 0.6, 0.6, 1)
    panel.collapseTex = collapseTex

    collapseBtn:SetScript("OnEnter", function()
        collapseTex:SetVertexColor(0.9, 0.9, 0.9, 1)
    end)
    collapseBtn:SetScript("OnLeave", function()
        collapseTex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    collapseBtn:SetScript("OnClick", function()
        panel:Toggle()
    end)

    -- Tab button definitions
    local TAB_DEFS = {
        { id = "output", label = "Output" },
        { id = "errors", label = "Errors" },
        { id = "events", label = "Events" },
    }

    local tabBtns = {}
    local tabXOffset = 24 -- after collapse button
    local tabBtnWidth = 70

    local function UpdateTabHighlights()
        for _, tb in ipairs(tabBtns) do
            if tb.id == panel.activeTab then
                tb.btn:SetBackdropColor(unpack(DF.Colors.bottomTabActiveBg))
                tb.label:SetTextColor(0.9, 0.9, 0.9, 1)
            else
                tb.btn:SetBackdropColor(unpack(DF.Colors.bottomTabInactiveBg))
                tb.label:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    end

    for i, def in ipairs(TAB_DEFS) do
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetSize(tabBtnWidth, L.bottomTabHeight)
        btn:SetPoint("LEFT", tabBar, "LEFT", tabXOffset + (i - 1) * (tabBtnWidth + 2), 0)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        })

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetPoint("LEFT", 6, 0)
        label:SetText(def.label)

        -- Badge count
        local badge = btn:CreateFontString(nil, "OVERLAY")
        badge:SetFont(DF.Fonts.ui, 9, "OUTLINE")
        badge:SetPoint("LEFT", label, "RIGHT", 4, 0)
        badge:SetTextColor(0.8, 0.3, 0.3, 1)
        badge:SetText("")

        btn:SetScript("OnClick", function()
            panel:SelectTab(def.id)
            if panel.collapsed then
                panel:Expand()
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if def.id ~= panel.activeTab then
                self:SetBackdropColor(unpack(DF.Colors.tabHover))
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if def.id ~= panel.activeTab then
                self:SetBackdropColor(unpack(DF.Colors.bottomTabInactiveBg))
            end
        end)

        tabBtns[i] = { id = def.id, btn = btn, label = label, badge = badge }
        panel.tabs[def.id] = tabBtns[i]
    end

    ---------------------------------------------------------------------------
    -- Content panes
    ---------------------------------------------------------------------------
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.contentArea = contentArea

    -- Output pane (shared ConsoleOutput + REPL input)
    local outputPane = CreateFrame("Frame", nil, contentArea)
    outputPane:SetAllPoints(contentArea)
    panel.outputPane = outputPane

    -- Create shared ConsoleOutput instance
    local sharedOutput = DF.ConsoleOutput:Create(outputPane)
    sharedOutput.frame:SetPoint("TOPLEFT", 0, 0)
    sharedOutput.frame:SetPoint("BOTTOMRIGHT", 0, 28)
    panel.sharedOutput = sharedOutput

    -- Welcome message for shared output
    sharedOutput:AddLine(DF.Colors.func .. "DevForge Output|r")
    sharedOutput:AddLine(DF.Colors.dim .. "Code execution results appear here.|r")
    sharedOutput:AddLine("")

    -- REPL input at the bottom
    local replInput = DF.ConsoleInput:Create(outputPane)
    replInput.frame:SetPoint("BOTTOMLEFT", 0, 0)
    replInput.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.replInput = replInput

    -- Initialize console history for REPL
    DF.ConsoleHistory:Init()

    -- Wire REPL execution
    replInput:SetOnExecute(function(code)
        DF.ConsoleHistory:Add(code)
        sharedOutput:AddLine(DF.Colors.func .. "> |r" .. DF.Colors.text .. code .. "|r")
        local result = DF.ConsoleExec:Execute(code)
        local lines = DF.ConsoleExec:FormatResults(result)
        if #lines > 0 then
            sharedOutput:AddLines(lines)
        end
        sharedOutput:AddLine("")
        -- Also fire for integration
        DF.EventBus:Fire("DF_OUTPUT_LINE", nil, nil)
    end)

    -- Errors pane
    local errorsPane = CreateFrame("Frame", nil, contentArea)
    errorsPane:SetAllPoints(contentArea)
    errorsPane:Hide()
    panel.errorsPane = errorsPane

    local errorsOutput = DF.ConsoleOutput:Create(errorsPane)
    errorsOutput.frame:SetAllPoints(errorsPane)
    panel.errorsOutput = errorsOutput

    -- Events pane
    local eventsPane = CreateFrame("Frame", nil, contentArea)
    eventsPane:SetAllPoints(contentArea)
    eventsPane:Hide()
    panel.eventsPane = eventsPane

    local eventsOutput = DF.ConsoleOutput:Create(eventsPane)
    eventsOutput.frame:SetAllPoints(eventsPane)
    panel.eventsOutput = eventsOutput

    ---------------------------------------------------------------------------
    -- Error feed integration
    ---------------------------------------------------------------------------
    local errorCount = 0

    -- Wire ErrorHandler callback immediately. BottomPanel is created after
    -- ADDON_LOADED, so ErrorHandler:Init() has already run by now.
    if DF.ErrorHandler then
        DF.ErrorHandler:SetOnNewError(function(err, isDuplicate)
            -- Feed to bottom panel
            if not isDuplicate then
                errorCount = errorCount + 1
                panel:SetBadge("errors", errorCount)
                errorsOutput:AddLine(
                    DF.Colors.dim .. (err.time or "") .. "|r  " ..
                    DF.Colors.error .. (err.message or "?") .. "|r"
                )
            end
            -- Forward to ErrorMonitor module
            DF.EventBus:Fire("DF_ERROR_RECEIVED", err, isDuplicate)
        end)
    end

    ---------------------------------------------------------------------------
    -- Event feed integration
    ---------------------------------------------------------------------------
    local eventCount = 0
    DF.EventBus:On("DF_EVENT_CAPTURED", function(eventName, timestamp)
        eventCount = eventCount + 1
        panel:SetBadge("events", eventCount)
        eventsOutput:AddLine(
            DF.Colors.dim .. format("%.1f", timestamp or 0) .. "|r  " ..
            DF.Colors.keyword .. (eventName or "?") .. "|r"
        )
    end)

    DF.EventBus:On("DF_EVENTS_CLEARED", function()
        eventCount = 0
        panel:SetBadge("events", 0)
        eventsOutput:Clear()
    end)

    DF.EventBus:On("DF_ERRORS_CLEARED", function()
        errorCount = 0
        panel:SetBadge("errors", 0)
        errorsOutput:Clear()
    end)

    ---------------------------------------------------------------------------
    -- Tab selection
    ---------------------------------------------------------------------------
    function panel:SelectTab(tabId)
        self.activeTab = tabId
        outputPane:Hide()
        errorsPane:Hide()
        eventsPane:Hide()

        if tabId == "output" then
            outputPane:Show()
        elseif tabId == "errors" then
            errorsPane:Show()
            errorCount = 0
            self:SetBadge("errors", 0)
        elseif tabId == "events" then
            eventsPane:Show()
            eventCount = 0
            self:SetBadge("events", 0)
        end

        UpdateTabHighlights()

        if DevForgeDB then
            DevForgeDB.bottomActiveTab = tabId
        end
    end

    ---------------------------------------------------------------------------
    -- Collapse / Expand
    ---------------------------------------------------------------------------
    function panel:Toggle()
        if self.collapsed then
            self:Expand()
        else
            self:Collapse()
        end
    end

    function panel:Collapse()
        self.collapsed = true
        contentArea:Hide()
        collapseTex:SetRotation(-math.pi / 2) -- point down
        self:SaveState()
        DF.EventBus:Fire("DF_BOTTOM_PANEL_TOGGLED", false)
    end

    function panel:Expand()
        self.collapsed = false
        contentArea:Show()
        collapseTex:SetRotation(math.pi / 2) -- point up
        self:SaveState()
        DF.EventBus:Fire("DF_BOTTOM_PANEL_TOGGLED", true)
    end

    function panel:IsCollapsed()
        return self.collapsed
    end

    function panel:GetHeight()
        return self.height
    end

    function panel:SetHeight(h)
        self.height = DF.Util:Clamp(h, L.bottomMinH, L.bottomMaxH)
        self:SaveState()
    end

    ---------------------------------------------------------------------------
    -- Output API (used by IntegrationBus and other modules)
    ---------------------------------------------------------------------------
    function panel:AddOutput(text, color)
        if color then
            sharedOutput:AddLine(color .. text .. "|r")
        else
            sharedOutput:AddLine(text)
        end
    end

    function panel:GetInputLine()
        return replInput
    end

    function panel:GetSharedOutput()
        return sharedOutput
    end

    function panel:ClearOutput()
        sharedOutput:Clear()
    end

    ---------------------------------------------------------------------------
    -- Badge management
    ---------------------------------------------------------------------------
    function panel:SetBadge(tabId, count)
        local tb = self.tabs[tabId]
        if not tb then return end
        if count and count > 0 then
            tb.badge:SetText("(" .. (count > 99 and "99+" or count) .. ")")
        else
            tb.badge:SetText("")
        end
        -- Also update activity bar badges for corresponding modules
        if tabId == "errors" and DF.activityBar then
            DF.activityBar:SetBadge("ErrorHandler", count)
        elseif tabId == "events" and DF.activityBar then
            DF.activityBar:SetBadge("EventMonitor", count)
        end
    end

    ---------------------------------------------------------------------------
    -- State persistence
    ---------------------------------------------------------------------------
    function panel:SaveState()
        if DevForgeDB then
            DevForgeDB.bottomHeight = self.height
            DevForgeDB.bottomCollapsed = self.collapsed
            DevForgeDB.bottomActiveTab = self.activeTab
        end
    end

    function panel:RestoreState()
        if DevForgeDB then
            self.height = DevForgeDB.bottomHeight or L.bottomDefaultH
            self.collapsed = DevForgeDB.bottomCollapsed or false
            self.activeTab = DevForgeDB.bottomActiveTab or "output"
        end
    end

    -- Initialize tab display
    UpdateTabHighlights()

    return panel
end
