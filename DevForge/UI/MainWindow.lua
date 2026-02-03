local _, DF = ...

DF.UI = DF.UI or {}
DF.UI.MainWindow = {}

local MainWin = DF.UI.MainWindow

function MainWin:Create()
    if DF.MainWindow then return end

    local L = DF.Layout

    local frame = CreateFrame("Frame", "DevForgeMainWindow", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(L.windowMinW, L.windowMinH)
    frame:SetToplevel(true)

    -- Restore or default size/position
    local db = DevForgeDB
    local w = db and db.windowW or L.windowDefaultW
    local h = db and db.windowH or L.windowDefaultH
    frame:SetSize(w, h)

    if db and db.windowX and db.windowY then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.windowX, db.windowY)
    else
        frame:SetPoint("CENTER")
    end

    -- Dialog chrome
    DF.Theme:ApplyDialogChrome(frame)

    ---------------------------------------------------------------------------
    -- Title bar area (for dragging)
    ---------------------------------------------------------------------------
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(L.titleHeight)
    titleBar:SetPoint("TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", -8, -8)
    DF.Theme:ApplyTitleBar(frame, titleBar)

    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        MainWin:SavePosition()
    end)

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFontObject(DF.Theme:UIFont())
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetText("DevForge")
    titleText:SetTextColor(0.6, 0.75, 1, 1)

    -- Version text
    local versionText = titleBar:CreateFontString(nil, "OVERLAY")
    versionText:SetFontObject(DF.Theme:UIFont())
    versionText:SetPoint("LEFT", titleText, "RIGHT", 6, 0)
    versionText:SetText("v" .. DF.ADDON_VERSION)
    versionText:SetTextColor(0.45, 0.45, 0.45, 1)

    -- Taint warning label + info button
    local taintText = titleBar:CreateFontString(nil, "OVERLAY")
    taintText:SetFontObject(DF.Theme:UIFont())
    taintText:SetPoint("RIGHT", -50, 0)
    taintText:SetText("[tainted execution]")
    taintText:SetTextColor(0.6, 0.4, 0.2, 0.6)

    local infoBtn = CreateFrame("Button", nil, titleBar)
    infoBtn:SetSize(32, 32)
    infoBtn:SetPoint("LEFT", taintText, "RIGHT", 3, 0)
    local infoBtnIcon = infoBtn:CreateTexture(nil, "OVERLAY")
    infoBtnIcon:SetSize(32, 32)
    infoBtnIcon:SetPoint("CENTER", 0, 0)
    infoBtnIcon:SetTexture(616343)
    infoBtnIcon:SetVertexColor(0.5, 0.5, 0.5, 0.8)

    local TAINT_HELPTIP = {
        text = "Code run via the Console and Snippet Editor uses loadstring(), which is tainted (same as /run).\n\nProtected functions (CastSpellByName, UseAction, etc.) cannot be called from tainted code.",
        buttonStyle = HelpTip.ButtonStyle.GotIt,
        targetPoint = HelpTip.Point.BottomEdgeCenter,
        alignment = HelpTip.Alignment.Center,
    }

    infoBtn:SetScript("OnEnter", function()
        infoBtnIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    infoBtn:SetScript("OnLeave", function()
        infoBtnIcon:SetVertexColor(0.5, 0.5, 0.5, 0.8)
    end)
    infoBtn:SetScript("OnClick", function(self)
        if HelpTip:IsShowing(self, TAINT_HELPTIP.text) then
            HelpTip:Hide(self, TAINT_HELPTIP.text)
        else
            HelpTip:Show(self, TAINT_HELPTIP)
        end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    ---------------------------------------------------------------------------
    -- Workspace area (below title bar)
    ---------------------------------------------------------------------------
    local workspace = CreateFrame("Frame", nil, frame)
    workspace:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
    workspace:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 28)
    frame.workspace = workspace

    ---------------------------------------------------------------------------
    -- Activity Bar (left edge)
    ---------------------------------------------------------------------------
    local activityBar = DF.UI.ActivityBar:Create(workspace)
    activityBar.frame:SetPoint("TOPLEFT", 0, 0)
    activityBar.frame:SetPoint("BOTTOMLEFT", 0, 0)
    DF.activityBar = activityBar

    ---------------------------------------------------------------------------
    -- Sidebar (left panel, after activity bar)
    ---------------------------------------------------------------------------
    local sidebar = DF.UI.Sidebar:Create(workspace)
    sidebar:RestoreState()
    sidebar.frame:SetPoint("TOPLEFT", activityBar.frame, "TOPRIGHT", 0, 0)
    sidebar.frame:SetPoint("BOTTOMLEFT", activityBar.frame, "BOTTOMRIGHT", 0, 0)
    sidebar.frame:SetWidth(sidebar.width)
    DF.sidebar = sidebar

    ---------------------------------------------------------------------------
    -- Sidebar splitter (between sidebar and main area)
    ---------------------------------------------------------------------------
    local sidebarSplitter = CreateFrame("Button", nil, workspace)
    sidebarSplitter:SetWidth(L.splitterWidth)
    sidebarSplitter:SetPoint("TOPLEFT", sidebar.frame, "TOPRIGHT", 0, 0)
    sidebarSplitter:SetPoint("BOTTOMLEFT", sidebar.frame, "BOTTOMRIGHT", 0, 0)
    DF.sidebarSplitter = sidebarSplitter

    local sbSplitTex = sidebarSplitter:CreateTexture(nil, "BACKGROUND")
    sbSplitTex:SetAllPoints()
    sbSplitTex:SetColorTexture(unpack(DF.Colors.splitter))

    local sbSplitHl = sidebarSplitter:CreateTexture(nil, "HIGHLIGHT")
    sbSplitHl:SetAllPoints()
    sbSplitHl:SetColorTexture(0.4, 0.6, 0.9, 0.3)

    -- Sidebar drag resize
    sidebarSplitter:EnableMouse(true)
    sidebarSplitter:RegisterForDrag("LeftButton")
    local sbDragging = false
    local sbDragStart, sbDragStartSize

    sidebarSplitter:SetScript("OnDragStart", function()
        sbDragging = true
        local cx = GetCursorPosition()
        local scale = sidebarSplitter:GetEffectiveScale()
        sbDragStart = cx / scale
        sbDragStartSize = sidebar.width
    end)
    sidebarSplitter:SetScript("OnDragStop", function()
        sbDragging = false
    end)
    sidebarSplitter:SetScript("OnUpdate", function()
        if not sbDragging then return end
        local cx = GetCursorPosition()
        local scale = sidebarSplitter:GetEffectiveScale()
        local delta = (cx / scale) - sbDragStart
        local newW = DF.Util:Clamp(sbDragStartSize + delta, L.sidebarMinW, L.sidebarMaxW)
        sidebar:SetWidth(newW)
        sidebar.frame:SetWidth(newW)
    end)

    ---------------------------------------------------------------------------
    -- Main area (right of sidebar splitter)
    ---------------------------------------------------------------------------
    local mainArea = CreateFrame("Frame", nil, workspace)
    mainArea:SetPoint("TOPLEFT", sidebarSplitter, "TOPRIGHT", 0, 0)
    mainArea:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.mainArea = mainArea

    ---------------------------------------------------------------------------
    -- Editor content area (top part of main area)
    ---------------------------------------------------------------------------
    local editorContent = CreateFrame("Frame", nil, mainArea)
    frame.editorContent = editorContent

    ---------------------------------------------------------------------------
    -- Bottom panel splitter (between editor and bottom panel)
    ---------------------------------------------------------------------------
    local bottomSplitter = CreateFrame("Button", nil, mainArea)
    bottomSplitter:SetHeight(L.splitterWidth)

    local btSplitTex = bottomSplitter:CreateTexture(nil, "BACKGROUND")
    btSplitTex:SetAllPoints()
    btSplitTex:SetColorTexture(unpack(DF.Colors.splitter))

    local btSplitHl = bottomSplitter:CreateTexture(nil, "HIGHLIGHT")
    btSplitHl:SetAllPoints()
    btSplitHl:SetColorTexture(0.4, 0.6, 0.9, 0.3)

    -- Bottom panel drag resize
    bottomSplitter:EnableMouse(true)
    bottomSplitter:RegisterForDrag("LeftButton")
    local btDragging = false
    local btDragStart, btDragStartSize

    bottomSplitter:SetScript("OnDragStart", function()
        btDragging = true
        local _, cy = GetCursorPosition()
        local scale = bottomSplitter:GetEffectiveScale()
        btDragStart = cy / scale
        btDragStartSize = DF.bottomPanel.height
    end)
    bottomSplitter:SetScript("OnDragStop", function()
        btDragging = false
    end)
    bottomSplitter:SetScript("OnUpdate", function()
        if not btDragging then return end
        local _, cy = GetCursorPosition()
        local scale = bottomSplitter:GetEffectiveScale()
        local delta = btDragStart - (cy / scale) -- inverted: drag down = larger
        local newH = DF.Util:Clamp(btDragStartSize + delta, L.bottomMinH, L.bottomMaxH)
        DF.bottomPanel:SetHeight(newH)
        MainWin:UpdateLayout()
    end)

    ---------------------------------------------------------------------------
    -- Bottom Panel
    ---------------------------------------------------------------------------
    local bottomPanel = DF.UI.BottomPanel:Create(mainArea)
    bottomPanel:RestoreState()
    DF.bottomPanel = bottomPanel

    ---------------------------------------------------------------------------
    -- Layout function: positions editor, splitter, and bottom panel
    ---------------------------------------------------------------------------
    function MainWin:UpdateLayout()
        local bp = DF.bottomPanel
        local isCollapsed = bp.collapsed
        local isConsoleActive = (DF.ModuleSystem:GetActive() == "Console")

        editorContent:ClearAllPoints()
        bottomSplitter:ClearAllPoints()
        bp.frame:ClearAllPoints()

        if isConsoleActive then
            -- Console takes over: hide editor, bottom panel fills main area
            editorContent:Hide()
            bottomSplitter:Hide()
            bp.frame:SetPoint("TOPLEFT", mainArea, "TOPLEFT", 0, 0)
            bp.frame:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, 0)
            bp.frame:Show()
            if bp.collapsed then
                bp:Expand()
            end
        elseif isCollapsed then
            -- Bottom panel collapsed: just show tab bar strip
            editorContent:Show()
            editorContent:SetPoint("TOPLEFT", mainArea, "TOPLEFT", 0, 0)
            editorContent:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, L.bottomTabHeight + 1)

            bottomSplitter:Hide()

            bp.frame:Show()
            bp.frame:SetPoint("BOTTOMLEFT", mainArea, "BOTTOMLEFT", 0, 0)
            bp.frame:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, 0)
            bp.frame:SetHeight(L.bottomTabHeight)
        else
            -- Normal: editor on top, splitter, bottom panel
            local bpHeight = bp.height

            editorContent:Show()
            editorContent:SetPoint("TOPLEFT", mainArea, "TOPLEFT", 0, 0)
            editorContent:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, bpHeight + L.splitterWidth)

            bottomSplitter:Show()
            bottomSplitter:SetPoint("BOTTOMLEFT", mainArea, "BOTTOMLEFT", 0, bpHeight)
            bottomSplitter:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, bpHeight)

            bp.frame:Show()
            bp.frame:SetPoint("BOTTOMLEFT", mainArea, "BOTTOMLEFT", 0, 0)
            bp.frame:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", 0, 0)
            bp.frame:SetHeight(bpHeight)
        end

        -- Handle sidebar collapsed state
        -- Sidebar frame stays visible (shows toggle button); splitter hides when collapsed
        if sidebar.collapsed then
            sidebarSplitter:Hide()
            mainArea:ClearAllPoints()
            mainArea:SetPoint("TOPLEFT", sidebar.frame, "TOPRIGHT", 0, 0)
            mainArea:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", 0, 0)
        else
            sidebarSplitter:Show()
            mainArea:ClearAllPoints()
            mainArea:SetPoint("TOPLEFT", sidebarSplitter, "TOPRIGHT", 0, 0)
            mainArea:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- React to sidebar/bottom toggle events
    DF.EventBus:On("DF_SIDEBAR_TOGGLED", function()
        MainWin:UpdateLayout()
    end, "MainWindow")

    DF.EventBus:On("DF_BOTTOM_PANEL_TOGGLED", function()
        MainWin:UpdateLayout()
    end, "MainWindow")

    -- React to module activation (Console dual mode)
    DF.EventBus:On("DF_MODULE_ACTIVATED", function()
        MainWin:UpdateLayout()
    end, "MainWindow")

    ---------------------------------------------------------------------------
    -- Resize grip (bottom-right corner)
    ---------------------------------------------------------------------------
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        MainWin:SavePosition()
        MainWin:UpdateLayout()
        DF.EventBus:Fire("DF_WINDOW_RESIZED", frame:GetWidth(), frame:GetHeight())
    end)

    ---------------------------------------------------------------------------
    -- Hide on Escape
    ---------------------------------------------------------------------------
    table.insert(UISpecialFrames, "DevForgeMainWindow")

    -- Deactivate module on hide, reactivate on show
    frame:SetScript("OnHide", function()
        MainWin:SavePosition()
        DF.ModuleSystem:DeactivateCurrent()
    end)
    frame:SetScript("OnShow", function()
        DF.ModuleSystem:ReactivateCurrent()
        MainWin:UpdateLayout()
    end)

    ---------------------------------------------------------------------------
    -- Store references
    ---------------------------------------------------------------------------
    DF.MainWindow = frame

    -- Legacy compatibility: modules that call GetContentParent() get editorContent
    frame.content = editorContent

    -- Initial layout
    MainWin:UpdateLayout()

    -- Select initial tab
    local bottomTab = (DevForgeDB and DevForgeDB.bottomActiveTab) or "output"
    bottomPanel:SelectTab(bottomTab)

    -- Apply sidebar collapsed state
    if sidebar.collapsed then
        sidebar:Collapse()
    end

    -- Apply bottom collapsed state
    if bottomPanel.collapsed then
        bottomPanel.contentArea:Hide()
        bottomPanel.collapseTex:SetRotation(-math.pi / 2)
    end

    -- Activate pending module or last module
    local targetModule = DF._pendingModule or (DevForgeDB and DevForgeDB.lastModule) or "Console"
    DF._pendingModule = nil
    C_Timer.After(0, function()
        DF.ModuleSystem:Activate(targetModule)
    end)
end

function MainWin:SavePosition()
    if not DF.MainWindow or not DevForgeDB then return end
    local f = DF.MainWindow
    local ok = pcall(function()
        local left = f:GetLeft()
        local top = f:GetTop()
        local w = f:GetWidth()
        local h = f:GetHeight()
        if left and top and w and h and w > 0 and h > 0 then
            DevForgeDB.windowX = left
            DevForgeDB.windowY = top
            DevForgeDB.windowW = w
            DevForgeDB.windowH = h
        end
    end)
end
