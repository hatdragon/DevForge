local _, DF = ...

-- Register the Snippet Editor module with sidebar + editor split
DF.ModuleSystem:Register("SnippetEditor", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local editor = {}
    local activeTabId = nil
    local openTabs = {}  -- ordered list of open snippet ids
    local ranProjects = {}  -- [projectId] = true for projects that have been run

    ---------------------------------------------------------------------------
    -- Sidebar: toggle bar + snippet list + template browser
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    -- Toggle bar at top of sidebar
    local toggleBar = CreateFrame("Frame", nil, sidebarFrame)
    toggleBar:SetHeight(22)
    toggleBar:SetPoint("TOPLEFT", 0, 0)
    toggleBar:SetPoint("TOPRIGHT", 0, 0)

    local function CreateToggleButton(parent, text, width)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetSize(width, 20)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        })

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFontObject(DF.Theme:UIFont())
        btn.label:SetPoint("CENTER", 0, 0)
        btn.label:SetText(text)
        btn.label:SetTextColor(0.65, 0.65, 0.65, 1)

        btn:SetScript("OnEnter", function(self)
            if not self.isActive then
                self:SetBackdropColor(unpack(DF.Colors.tabHover))
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self.isActive then
                self:SetBackdropColor(unpack(DF.Colors.tabInactive))
            end
        end)

        function btn:SetActive(active)
            self.isActive = active
            if active then
                self:SetBackdropColor(unpack(DF.Colors.tabActive))
                self.label:SetTextColor(0.83, 0.83, 0.83, 1)
            else
                self:SetBackdropColor(unpack(DF.Colors.tabInactive))
                self.label:SetTextColor(0.65, 0.65, 0.65, 1)
            end
        end

        btn:SetActive(false)
        return btn
    end

    local snippetsToggle = CreateToggleButton(toggleBar, "Snippets", 70)
    snippetsToggle:SetPoint("LEFT", 2, 0)

    local templatesToggle = CreateToggleButton(toggleBar, "Templates", 70)
    templatesToggle:SetPoint("LEFT", snippetsToggle, "RIGHT", 2, 0)

    -- Snippets container
    local snippetsContainer = CreateFrame("Frame", nil, sidebarFrame)
    snippetsContainer:SetPoint("TOPLEFT", toggleBar, "BOTTOMLEFT", 0, -2)
    snippetsContainer:SetPoint("BOTTOMRIGHT", 0, 0)

    local snippetSearch = DF.Widgets:CreateSearchBox(snippetsContainer, "Filter snippets...", 22)
    snippetSearch.frame:SetPoint("TOPLEFT", snippetsContainer, "TOPLEFT", 2, -2)
    snippetSearch.frame:SetPoint("TOPRIGHT", snippetsContainer, "TOPRIGHT", -2, -2)

    local snippetList = DF.SnippetList:Create(snippetsContainer)
    snippetList.frame:SetPoint("TOPLEFT", snippetSearch.frame, "BOTTOMLEFT", 0, -2)
    snippetList.frame:SetPoint("BOTTOMRIGHT", snippetsContainer, "BOTTOMRIGHT", 0, 0)

    snippetSearch:SetOnSearch(function(text)
        snippetList:SetFilter(text)
    end)

    -- Running-projects panel (bottom of sidebar, hidden until first run)
    local runPanel = CreateFrame("Frame", nil, snippetsContainer, "BackdropTemplate")
    runPanel:SetPoint("BOTTOMLEFT", 0, 0)
    runPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    runPanel:Hide()
    local runPanelBg = runPanel:CreateTexture(nil, "BACKGROUND")
    runPanelBg:SetAllPoints()
    runPanelBg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local runPanelSep = runPanel:CreateTexture(nil, "OVERLAY")
    runPanelSep:SetHeight(1)
    runPanelSep:SetPoint("TOPLEFT", 0, 0)
    runPanelSep:SetPoint("TOPRIGHT", 0, 0)
    runPanelSep:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    local runPanelHeader = runPanel:CreateFontString(nil, "OVERLAY")
    runPanelHeader:SetFontObject(DF.Theme:UIFont())
    runPanelHeader:SetPoint("TOPLEFT", 6, -5)
    runPanelHeader:SetTextColor(0.9, 0.75, 0.3, 1)
    runPanelHeader:SetText("Running")

    local runPanelRows = {}

    local runPanelReload = DF.Widgets:CreateButton(runPanel, "Reload UI", 65)
    runPanelReload:SetPoint("BOTTOMLEFT", 6, 6)
    runPanelReload:SetScript("OnClick", function() ReloadUI() end)

    local function RefreshRunPanel()
        -- Collect running project names
        local entries = {}
        for projectId in pairs(ranProjects) do
            local proj = DF.SnippetStore:Get(projectId)
            if proj then
                entries[#entries + 1] = proj.name or "Untitled"
            end
        end
        table.sort(entries)

        if #entries == 0 then
            runPanel:Hide()
            snippetList.frame:SetPoint("BOTTOMRIGHT", snippetsContainer, "BOTTOMRIGHT", 0, 0)
            return
        end

        -- Create/update row labels
        for i, name in ipairs(entries) do
            if not runPanelRows[i] then
                local row = runPanel:CreateFontString(nil, "OVERLAY")
                row:SetFontObject(DF.Theme:UIFont())
                row:SetJustifyH("LEFT")
                row:SetTextColor(0.7, 0.7, 0.7, 1)
                runPanelRows[i] = row
            end
            runPanelRows[i]:SetText("  " .. name)
            runPanelRows[i]:ClearAllPoints()
            runPanelRows[i]:SetPoint("TOPLEFT", 6, -5 - (i * 16))
            runPanelRows[i]:SetPoint("RIGHT", -6, 0)
            runPanelRows[i]:Show()
        end
        -- Hide extra rows
        for i = #entries + 1, #runPanelRows do
            runPanelRows[i]:Hide()
        end

        -- header + rows + button + padding
        local panelHeight = 10 + (#entries + 1) * 16 + 28
        runPanel:SetHeight(panelHeight)
        runPanel:Show()
        snippetList.frame:SetPoint("BOTTOMRIGHT", snippetsContainer, "BOTTOMRIGHT", 0, panelHeight)
    end

    -- Templates container
    local templatesContainer = CreateFrame("Frame", nil, sidebarFrame)
    templatesContainer:SetPoint("TOPLEFT", toggleBar, "BOTTOMLEFT", 0, -2)
    templatesContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    templatesContainer:Hide()

    local templateBrowser = DF.TemplateBrowser:Create(templatesContainer)
    templateBrowser.frame:SetAllPoints(templatesContainer)

    -- Tab switching
    local function SetSidebarTab(tab)
        if tab == "templates" then
            snippetsContainer:Hide()
            templatesContainer:Show()
            snippetsToggle:SetActive(false)
            templatesToggle:SetActive(true)
        else
            tab = "snippets"
            templatesContainer:Hide()
            snippetsContainer:Show()
            templatesToggle:SetActive(false)
            snippetsToggle:SetActive(true)
        end
        if DevForgeDB then
            DevForgeDB.snippetSidebarTab = tab
        end
    end

    snippetsToggle:SetScript("OnClick", function() SetSidebarTab("snippets") end)
    templatesToggle:SetScript("OnClick", function() SetSidebarTab("templates") end)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + name bar + code editor
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local newBtn = DF.Widgets:CreateButton(toolbar, "+ New", 60)
    newBtn:SetPoint("LEFT", 2, 0)

    local dupBtn = DF.Widgets:CreateButton(toolbar, "Duplicate", 75)
    dupBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)

    local delBtn = DF.Widgets:CreateButton(toolbar, "Delete", 60)
    delBtn:SetPoint("LEFT", dupBtn, "RIGHT", 4, 0)

    -- Frame Builder and Scaffold buttons between Delete and Run
    local frameBuilderBtn = DF.Widgets:CreateButton(toolbar, "Frame Builder", 95)
    frameBuilderBtn:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)

    local scaffoldBtn = DF.Widgets:CreateButton(toolbar, "Scaffold", 70)
    scaffoldBtn:SetPoint("LEFT", frameBuilderBtn, "RIGHT", 4, 0)

    local runProjectBtn = DF.Widgets:CreateButton(toolbar, "Run Project", 80)
    runProjectBtn:SetPoint("LEFT", scaffoldBtn, "RIGHT", 4, 0)

    local saveBtn = DF.Widgets:CreateButton(toolbar, "Save", 55)
    saveBtn:SetPoint("RIGHT", -2, 0)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 55)
    copyBtn:SetPoint("RIGHT", saveBtn, "LEFT", -4, 0)

    local runBtn = DF.Widgets:CreateButton(toolbar, "Run", 55)
    runBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)

    -- Empty state
    local emptyState = editorFrame:CreateFontString(nil, "OVERLAY")
    emptyState:SetFontObject(DF.Theme:UIFont())
    emptyState:SetPoint("CENTER", 0, 0)
    emptyState:SetText("Create a snippet to get started.")
    emptyState:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Open-tabs strip (hidden when nothing is open)
    local tabStrip = DF.Widgets:CreateTabStrip(editorFrame)
    tabStrip.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    tabStrip.frame:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)
    tabStrip.frame:Hide()

    -- Run-project warning banner
    local runBanner = CreateFrame("Frame", nil, editorFrame, "BackdropTemplate")
    runBanner:SetHeight(20)
    runBanner:SetPoint("TOPLEFT", tabStrip.frame, "BOTTOMLEFT", 0, -2)
    runBanner:SetPoint("TOPRIGHT", tabStrip.frame, "BOTTOMRIGHT", 0, -2)
    runBanner:Hide()
    local runBannerBg = runBanner:CreateTexture(nil, "BACKGROUND")
    runBannerBg:SetAllPoints()
    runBannerBg:SetColorTexture(0.35, 0.25, 0.05, 0.6)
    local runBannerReload = DF.Widgets:CreateButton(runBanner, "Reload UI", 65)
    runBannerReload:SetPoint("RIGHT", -4, 0)
    runBannerReload:SetScript("OnClick", function() ReloadUI() end)

    local runBannerText = runBanner:CreateFontString(nil, "OVERLAY")
    runBannerText:SetFontObject(DF.Theme:UIFont())
    runBannerText:SetPoint("LEFT", 6, 0)
    runBannerText:SetPoint("RIGHT", runBannerReload, "LEFT", -6, 0)
    runBannerText:SetJustifyH("LEFT")
    runBannerText:SetTextColor(0.9, 0.75, 0.3, 1)
    runBannerText:SetText("Re-running won't unload previous frames or state.")

    -- Editor content (hidden when no snippet selected)
    local editorContent = CreateFrame("Frame", nil, editorFrame)
    editorContent:SetPoint("BOTTOMRIGHT", 0, 0)
    editorContent:Hide()

    local function UpdateEditorContentAnchor()
        editorContent:ClearAllPoints()
        if runBanner:IsShown() then
            editorContent:SetPoint("TOPLEFT", runBanner, "BOTTOMLEFT", 0, -2)
        elseif tabStrip.frame:IsShown() then
            editorContent:SetPoint("TOPLEFT", tabStrip.frame, "BOTTOMLEFT", 0, -2)
        else
            editorContent:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
        end
        editorContent:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    UpdateEditorContentAnchor()

    -- Name input row
    local nameRow = CreateFrame("Frame", nil, editorContent)
    nameRow:SetHeight(24)
    nameRow:SetPoint("TOPLEFT", 0, 0)
    nameRow:SetPoint("TOPRIGHT", 0, 0)

    local nameLabel = nameRow:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFontObject(DF.Theme:UIFont())
    nameLabel:SetPoint("LEFT", 4, 0)
    nameLabel:SetText("Name:")
    nameLabel:SetTextColor(0.65, 0.65, 0.65, 1)

    local nameInput = CreateFrame("EditBox", nil, nameRow, "BackdropTemplate")
    nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
    nameInput:SetPoint("RIGHT", -4, 0)
    nameInput:SetHeight(20)
    nameInput:SetAutoFocus(false)
    nameInput:SetFontObject(DF.Theme:UIFont())
    nameInput:SetTextColor(0.83, 0.83, 0.83, 1)
    nameInput:SetMaxLetters(100)
    DF.Theme:ApplyInputStyle(nameInput)

    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    DF.Util:HookSaveShortcut(nameInput, function() saveBtn:Click() end)

    -- Code editor (uses most of remaining space)
    local codeEditor = DF.Widgets:CreateCodeEditBox(editorContent, {
        multiLine = true,
        readOnly = false,
        autocomplete = true,
    })
    codeEditor.frame:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -2)
    codeEditor.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    codeEditor:SetOnSaveShortcut(function() saveBtn:Click() end)

    -- Frame Builder view: shown instead of codeEditor for snippets that
    -- carry a builderState (see FrameBuilder.lua's CreateEmbedded). Same
    -- region as codeEditor; codeEditor stays hidden and inert underneath
    -- so it never diverges from what the builder generates.
    local frameBuilder = DF.FrameBuilder:CreateEmbedded(editorContent)
    frameBuilder.frame:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -2)
    frameBuilder.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    frameBuilder.frame:Hide()

    ---------------------------------------------------------------------------
    -- Logic
    ---------------------------------------------------------------------------
    local function SaveCurrent()
        if not activeTabId then return end
        local name = nameInput:GetText()
        local code = codeEditor:GetText()
        DF.SnippetStore:Save(activeTabId, name, code)
    end

    -- Persists a Frame Builder edit: builderState is the source of truth,
    -- and snippet.code is kept mirroring the text generated from it so
    -- Run/Copy/"Run Project" keep working unchanged.
    local function OnBuilderChange(state, code)
        if not activeTabId then return end
        DF.SnippetStore:SaveBuilderState(activeTabId, state)
        DF.SnippetStore:Save(activeTabId, nil, code)
    end

    -- Rebuild the tab strip from openTabs + persist it
    local function RefreshTabStrip()
        local tabs = {}
        for _, id in ipairs(openTabs) do
            local snippet = DF.SnippetStore:Get(id)
            if snippet then
                tabs[#tabs + 1] = { id = id, label = snippet.name or "Untitled" }
            end
        end
        tabStrip:SetTabs(tabs)
        tabStrip:SetActive(activeTabId)
        tabStrip.frame:SetShown(#tabs > 0)
        UpdateEditorContentAnchor()
        if DevForgeDB then
            DevForgeDB.openSnippetTabs = openTabs
        end
    end

    -- Show a snippet's content in the shared editor pane. Does not affect
    -- which tabs are open; use OpenTab for that.
    local function ActivateTab(id)
        local snippet = id and DF.SnippetStore:Get(id)
        if not snippet then
            runBanner:Hide()
            activeTabId = nil
            UpdateEditorContentAnchor()
            editorContent:Hide()
            emptyState:Show()
            tabStrip:SetActive(nil)
            return
        end

        -- Show banner if this snippet belongs to any previously-run project
        local snippetProjectId = snippet.isProject and snippet.id or snippet.parentId
        if snippetProjectId and ranProjects[snippetProjectId] then
            runBanner:Show()
        else
            runBanner:Hide()
        end

        emptyState:Hide()
        editorContent:Show()
        UpdateEditorContentAnchor()

        activeTabId = id
        nameInput:SetText(snippet.name or "")
        codeEditor:SetText(snippet.code or "")
        if codeEditor.ResetUndo then codeEditor:ResetUndo() end
        snippetList:SetSelected(id)
        tabStrip:SetActive(id)

        if snippet.builderState then
            codeEditor.frame:Hide()
            frameBuilder.frame:Show()
            frameBuilder:LoadState(snippet.builderState, OnBuilderChange)
        else
            frameBuilder.frame:Hide()
            codeEditor.frame:Show()
        end

        if DevForgeDB then
            DevForgeDB.lastSnippetId = id
        end
    end

    -- Open a snippet in a tab (if not already open) and activate it
    local function OpenTab(id)
        if not id then
            ActivateTab(nil)
            return
        end
        local alreadyOpen = false
        for _, existing in ipairs(openTabs) do
            if existing == id then alreadyOpen = true; break end
        end
        if not alreadyOpen then
            openTabs[#openTabs + 1] = id
        end
        ActivateTab(id)
        RefreshTabStrip()
    end

    -- Close a tab without touching the underlying snippet. If it was active,
    -- activates the tab to its right, else its left, else shows empty state.
    local function CloseTab(id)
        local idx
        for i, existing in ipairs(openTabs) do
            if existing == id then idx = i; break end
        end
        if not idx then return end

        if activeTabId == id then
            SaveCurrent()
        end
        table.remove(openTabs, idx)

        if activeTabId == id then
            ActivateTab(openTabs[idx] or openTabs[idx - 1])
        end
        RefreshTabStrip()
    end

    -- Drop open tabs whose snippet no longer exists (after a delete),
    -- falling back to another open tab (or the empty state) if needed.
    local function PurgeMissingTabs()
        local kept = {}
        for _, id in ipairs(openTabs) do
            if DF.SnippetStore:Get(id) then
                kept[#kept + 1] = id
            end
        end
        openTabs = kept
        if activeTabId and not DF.SnippetStore:Get(activeTabId) then
            ActivateTab(openTabs[1])
        end
        RefreshTabStrip()
    end

    local function SelectNext()
        local topLevel = DF.SnippetStore:GetTopLevel()
        if #topLevel == 0 then
            OpenTab(nil)
            return
        end
        -- If the first top-level item is a project, select its first child
        local first = topLevel[1]
        if first.isProject then
            local children = DF.SnippetStore:GetChildren(first.id)
            if #children > 0 then
                OpenTab(children[1].id)
                return
            end
        end
        OpenTab(first.id)
    end

    -- Insert code at the cursor position in the active editor.
    -- If nothing is open, create a new snippet with the code.
    local function InsertCode(code, snippetName)
        if activeTabId then
            -- Insert at cursor position via the native EditBox Insert()
            codeEditor:Insert(code)
            SaveCurrent()
            snippetList:Refresh()
        else
            -- No snippet open; create one and load it
            SaveCurrent()
            local snippet = DF.SnippetStore:Create(snippetName or "Generated")
            DF.SnippetStore:Save(snippet.id, snippet.name, code)
            SetSidebarTab("snippets")
            snippetList:Refresh()
            OpenTab(snippet.id)
        end
    end

    ---------------------------------------------------------------------------
    -- Template selection flow: browser handles preview inline,
    -- fires onInsert only when the user clicks Insert
    ---------------------------------------------------------------------------
    templateBrowser:SetOnInsert(function(code, name)
        InsertCode(code, name)
    end)

    ---------------------------------------------------------------------------
    -- Toolbar button handlers
    ---------------------------------------------------------------------------
    local function CreateNew(parentId)
        SaveCurrent()
        local snippet = DF.SnippetStore:Create("Untitled", parentId)
        snippetList:Refresh()
        OpenTab(snippet.id)
        nameInput:SetFocus()
        nameInput:HighlightText()
    end

    snippetList:SetOnSelect(function(id)
        SaveCurrent()
        OpenTab(id)
    end)

    tabStrip:SetOnSelect(function(id)
        SaveCurrent()
        ActivateTab(id)
        RefreshTabStrip()
    end)

    tabStrip:SetOnAction(function(action, id)
        if action == "close" then
            CloseTab(id)
        elseif action == "closeOthers" then
            for _, existing in ipairs({ unpack(openTabs) }) do
                if existing ~= id then CloseTab(existing) end
            end
        elseif action == "closeAll" then
            for _, existing in ipairs({ unpack(openTabs) }) do
                CloseTab(existing)
            end
        end
    end)

    local contextMenu = DF.Widgets:CreateDropDown()

    snippetList:SetOnRightClick(function(snippetId, isProjectRow)
        local snippet = DF.SnippetStore:Get(snippetId)
        if not snippet then return end

        local items = {}
        if snippet.isProject then
            items[#items + 1] = {
                text = "New file in " .. (snippet.name or "project"),
                func = function()
                    snippetList:SetExpanded(snippetId, true)
                    CreateNew(snippetId)
                end,
            }
            local childCount = #DF.SnippetStore:GetChildren(snippetId)
            local label = "Delete project"
            if childCount > 0 then
                label = label .. " (" .. childCount .. " files)"
            end
            items[#items + 1] = {
                text = label,
                func = function()
                    DF.SnippetStore:Delete(snippetId)
                    snippetList:Refresh()
                    PurgeMissingTabs()
                end,
            }
        else
            items[#items + 1] = {
                text = "Delete snippet",
                func = function()
                    DF.SnippetStore:Delete(snippetId)
                    snippetList:Refresh()
                    PurgeMissingTabs()
                end,
            }
        end

        contextMenu:Show(nil, items)
    end)

    local newMenu = DF.Widgets:CreateDropDown()

    -- Lightweight project-name prompt (avoids StaticPopup quirks)
    local projectPrompt = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    projectPrompt:SetFrameStrata("FULLSCREEN_DIALOG")
    projectPrompt:SetSize(280, 80)
    projectPrompt:SetPoint("CENTER")
    projectPrompt:SetClampedToScreen(true)
    projectPrompt:EnableMouse(true)
    projectPrompt:Hide()
    DF.Theme:ApplyDialogChrome(projectPrompt)

    local ppLabel = projectPrompt:CreateFontString(nil, "OVERLAY")
    ppLabel:SetFontObject(DF.Theme:UIFont())
    ppLabel:SetPoint("TOPLEFT", 10, -10)
    ppLabel:SetText("Project name:")
    ppLabel:SetTextColor(0.65, 0.65, 0.65, 1)

    local ppInput = CreateFrame("EditBox", nil, projectPrompt, "BackdropTemplate")
    ppInput:SetPoint("TOPLEFT", 10, -28)
    ppInput:SetPoint("RIGHT", -10, 0)
    ppInput:SetHeight(22)
    ppInput:SetAutoFocus(false)
    ppInput:SetFontObject(DF.Theme:UIFont())
    ppInput:SetTextColor(0.83, 0.83, 0.83, 1)
    ppInput:SetMaxLetters(100)
    DF.Theme:ApplyInputStyle(ppInput)

    local ppCreate = DF.Widgets:CreateButton(projectPrompt, "Create", 60)
    ppCreate:SetPoint("BOTTOMRIGHT", -10, 8)

    local ppCancel = DF.Widgets:CreateButton(projectPrompt, "Cancel", 60)
    ppCancel:SetPoint("RIGHT", ppCreate, "LEFT", -4, 0)

    local function FinishProjectPrompt()
        local name = ppInput:GetText()
        if not name or name == "" then name = "Untitled Project" end
        projectPrompt:Hide()
        SaveCurrent()
        local project = DF.SnippetStore:CreateProject(name)
        snippetList:Refresh()
        snippetList:SetExpanded(project.id, true)
    end

    ppCreate:SetScript("OnClick", FinishProjectPrompt)
    ppCancel:SetScript("OnClick", function() projectPrompt:Hide() end)
    ppInput:SetScript("OnEnterPressed", FinishProjectPrompt)
    ppInput:SetScript("OnEscapePressed", function() projectPrompt:Hide() end)

    projectPrompt:SetScript("OnShow", function()
        ppInput:SetText("Untitled Project")
        ppInput:HighlightText()
        ppInput:SetFocus()
    end)

    local function CreateNewProject()
        projectPrompt:Show()
    end

    newBtn:SetScript("OnClick", function(self)
        -- Determine project context
        local projectId, projectName
        if activeTabId then
            local cur = DF.SnippetStore:Get(activeTabId)
            if cur then
                if cur.isProject then
                    projectId = cur.id
                    projectName = cur.name
                elseif cur.parentId then
                    local proj = DF.SnippetStore:Get(cur.parentId)
                    if proj then
                        projectId = proj.id
                        projectName = proj.name
                    end
                end
            end
        end

        local items = {}
        if projectId then
            items[#items + 1] = { text = "New in " .. projectName, func = function() CreateNew(projectId) end }
            items[#items + 1] = { text = "New standalone snippet", func = function() CreateNew(nil) end }
        else
            items[#items + 1] = { text = "New snippet", func = function() CreateNew(nil) end }
        end
        items[#items + 1] = { text = "New empty project", func = CreateNewProject }

        newMenu:Show(self, items)
    end)

    dupBtn:SetScript("OnClick", function()
        if not activeTabId then return end
        SaveCurrent()
        local clone = DF.SnippetStore:Duplicate(activeTabId)
        if clone then
            snippetList:Refresh()
            OpenTab(clone.id)
        end
    end)

    delBtn:SetScript("OnClick", function()
        if not activeTabId then return end
        DF.SnippetStore:Delete(activeTabId)
        snippetList:Refresh()
        PurgeMissingTabs()
    end)

    frameBuilderBtn:SetScript("OnClick", function()
        SaveCurrent()
        local snippet = DF.SnippetStore:Create("Untitled Frame")
        DF.SnippetStore:SaveBuilderState(snippet.id, {})
        snippetList:Refresh()
        OpenTab(snippet.id)
    end)

    scaffoldBtn:SetScript("OnClick", function()
        DF.AddonScaffold:Show(function(files, projectName)
            SaveCurrent()
            local project = DF.SnippetStore:CreateProject(projectName)
            for _, file in ipairs(files) do
                local s = DF.SnippetStore:Create(file.name, project.id)
                DF.SnippetStore:Save(s.id, s.name, file.code)
            end
            SetSidebarTab("snippets")
            snippetList:Refresh()
            -- Load the first child file
            local children = DF.SnippetStore:GetChildren(project.id)
            if #children > 0 then
                OpenTab(children[1].id)
            end
        end)
    end)

    -- Parse a .toc file's content and return ordered list of .lua filenames
    local function ParseTocLoadOrder(tocCode)
        local files = {}
        for line in tocCode:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$") -- trim
            if line ~= "" and line:sub(1, 2) ~= "##" then
                if line:match("%.lua$") then
                    files[#files + 1] = line
                end
            end
        end
        return files
    end

    runProjectBtn:SetScript("OnClick", function()
        if not activeTabId then return end
        if not DF.ConsoleExec then return end
        SaveCurrent()

        -- Ensure bottom panel is visible and on the Output tab
        local bp = DF.bottomPanel
        if bp then
            if bp.collapsed then bp:Expand() end
            bp:SelectTab("output")
        end

        -- Determine project context
        local snippet = DF.SnippetStore:Get(activeTabId)
        if not snippet or not snippet.parentId then return end

        local project = DF.SnippetStore:Get(snippet.parentId)
        if not project or not project.isProject then return end

        local children = DF.SnippetStore:GetChildren(project.id)
        if #children == 0 then return end

        -- Build lookup of children by name
        local childByName = {}
        for _, child in ipairs(children) do
            childByName[child.name] = child
        end

        -- Find the .toc file
        local tocChild = childByName[project.name .. ".toc"]
        if not tocChild then
            DF.EventBus:Fire("DF_OUTPUT_LINE", {
                text = "No .toc file found in project (expected " .. project.name .. ".toc)",
                color = DF.Colors.error,
            })
            return
        end

        -- Parse load order
        local loadOrder = ParseTocLoadOrder(tocChild.code or "")
        if #loadOrder == 0 then
            DF.EventBus:Fire("DF_OUTPUT_LINE", {
                text = "No .lua files listed in " .. tocChild.name,
                color = DF.Colors.error,
            })
            return
        end

        -- Header
        DF.EventBus:Fire("DF_OUTPUT_LINE", {
            text = "=== Run Project: " .. project.name .. " ===",
            color = DF.Colors.func,
        })

        -- Shared namespace
        local ns = {}
        local addonName = project.name
        local filesRun, filesErrored = 0, 0

        -- Memory baseline for Perf tracking
        collectgarbage("collect")
        local memBefore = collectgarbage("count")
        local cpuAccum = 0   -- microseconds accumulated by wrapped frame scripts
        local trackedFrames = {}

        -- Unregister previous virtual entry if re-running
        local debugKey = "debug:" .. project.id
        if ranProjects[project.id] then
            DF.PerfData:UnregisterVirtual(debugKey)
        end

        -- Track frames that register for lifecycle events during execution
        -- so we can simulate them after all files are loaded.
        -- IMPORTANT: The CreateFrame wrapper stays active during event simulation
        -- so that frames created by event handlers (e.g. ns.Init() called from PEW)
        -- also get their lifecycle events tracked and fired in subsequent passes.
        local addonLoadedFrames = {}
        local playerLoginFrames = {}
        local enteringWorldFrames = {}
        local realCreateFrame = CreateFrame
        local frameSeen = {} -- prevent duplicate tracking
        CreateFrame = function(frameType, ...)
            local frame = realCreateFrame(frameType, ...)
            trackedFrames[#trackedFrames + 1] = frame
            local realRegisterEvent = frame.RegisterEvent
            frame.RegisterEvent = function(self, event, ...)
                local key = tostring(self) .. event
                if frameSeen[key] then
                    return realRegisterEvent(self, event, ...)
                end
                frameSeen[key] = true
                if event == "ADDON_LOADED" then
                    addonLoadedFrames[#addonLoadedFrames + 1] = self
                elseif event == "PLAYER_LOGIN" then
                    playerLoginFrames[#playerLoginFrames + 1] = self
                elseif event == "PLAYER_ENTERING_WORLD" then
                    enteringWorldFrames[#enteringWorldFrames + 1] = self
                end
                return realRegisterEvent(self, event, ...)
            end
            return frame
        end

        for _, filename in ipairs(loadOrder) do
            local child = childByName[filename]
            if child and child.code and child.code ~= "" then
                -- File header
                DF.EventBus:Fire("DF_OUTPUT_LINE", {
                    text = "-- " .. addonName .. "/" .. filename,
                    color = DF.Colors.func,
                })

                local result = DF.ConsoleExec:ExecuteFile(child.code, addonName, ns)
                local lines = DF.ConsoleExec:FormatResults(result)

                for _, line in ipairs(lines) do
                    DF.EventBus:Fire("DF_OUTPUT_LINE", { text = line })
                end

                filesRun = filesRun + 1
                if not result.success then
                    filesErrored = filesErrored + 1
                end
            else
                DF.EventBus:Fire("DF_OUTPUT_LINE", {
                    text = "-- Skipped (not found): " .. filename,
                    color = DF.Colors.dim,
                })
            end
        end

        -- Simulate lifecycle events with cascading: handlers may create new frames
        -- that register for later events. We loop until no new frames appear.
        -- WoW order: ADDON_LOADED → PLAYER_LOGIN → PLAYER_ENTERING_WORLD
        local processedAL, processedLogin, processedPEW = 0, 0, 0
        local maxPasses = 5

        -- Helper: fire an event on unprocessed frames, capture print output
        local function FireEvent(eventName, frames, processed, ...)
            if processed >= #frames then return processed end

            DF.EventBus:Fire("DF_OUTPUT_LINE", {
                text = "-- Firing " .. eventName,
                color = DF.Colors.comment,
            })

            local prints = {}
            local origPrint = print
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    local v = select(i, ...)
                    parts[i] = DF.SecretGuard:FormatValue(v) or tostring(v)
                end
                prints[#prints + 1] = table.concat(parts, "    ")
            end

            local eventArgs = { ... }
            local nArgs = select("#", ...)
            while processed < #frames do
                processed = processed + 1
                local frame = frames[processed]
                local handler = frame:GetScript("OnEvent")
                if handler then
                    local ok, err = pcall(handler, frame, eventName, unpack(eventArgs, 1, nArgs))
                    if not ok then
                        prints[#prints + 1] = DF.Colors.error .. tostring(err) .. "|r"
                        filesErrored = filesErrored + 1
                    end
                end
            end

            print = origPrint

            for _, line in ipairs(prints) do
                DF.EventBus:Fire("DF_OUTPUT_LINE", { text = DF.Colors.text .. line .. "|r" })
            end

            return processed
        end

        for pass = 1, maxPasses do
            local alBefore = #addonLoadedFrames
            local loginBefore = #playerLoginFrames
            local pewBefore = #enteringWorldFrames

            processedAL = FireEvent("ADDON_LOADED", addonLoadedFrames, processedAL, addonName)
            processedLogin = FireEvent("PLAYER_LOGIN", playerLoginFrames, processedLogin)
            processedPEW = FireEvent("PLAYER_ENTERING_WORLD", enteringWorldFrames, processedPEW, true, false)

            -- If no new frames were added during this pass, we're done
            local hadNew = (#addonLoadedFrames > alBefore)
                or (#playerLoginFrames > loginBefore)
                or (#enteringWorldFrames > pewBefore)
            if not hadNew then break end
        end

        -- Restore CreateFrame AFTER all simulation is complete
        CreateFrame = realCreateFrame

        -- Measure memory allocation and register Perf virtual entry
        local memAfter = collectgarbage("count")
        local memUsed = math.max(0, memAfter - memBefore)

        -- Wrap OnUpdate/OnEvent on tracked frames for live CPU measurement
        for _, frame in ipairs(trackedFrames) do
            local origOnUpdate = frame:GetScript("OnUpdate")
            if origOnUpdate then
                frame:SetScript("OnUpdate", function(self, elapsed)
                    local t0 = debugprofilestop()
                    origOnUpdate(self, elapsed)
                    cpuAccum = cpuAccum + (debugprofilestop() - t0)
                end)
            end
            local origOnEvent = frame:GetScript("OnEvent")
            if origOnEvent then
                frame:SetScript("OnEvent", function(self, event, ...)
                    local t0 = debugprofilestop()
                    origOnEvent(self, event, ...)
                    cpuAccum = cpuAccum + (debugprofilestop() - t0)
                end)
            end
        end

        -- Register virtual entry in PerfData
        local snap = DF.PerfData:RegisterVirtual(debugKey, "DEBUG: " .. project.name, function()
            return { cpu = cpuAccum / 1000 }  -- convert μs to ms
        end)
        snap.memory = memUsed
        snap.memoryPeak = memUsed

        -- Summary
        local summary = filesRun .. " file(s) executed"
        if filesErrored > 0 then
            summary = summary .. ", " .. filesErrored .. " with errors"
        end
        DF.EventBus:Fire("DF_OUTPUT_LINE", {
            text = "=== " .. summary .. " ===",
            color = DF.Colors.func,
        })
        DF.EventBus:Fire("DF_OUTPUT_LINE", { text = "" })

        ranProjects[project.id] = true
        runBanner:Show()
        UpdateEditorContentAnchor()
        RefreshRunPanel()
    end)

    saveBtn:SetScript("OnClick", function()
        SaveCurrent()
        snippetList:Refresh()
        RefreshTabStrip()
    end)

    copyBtn:SetScript("OnClick", function()
        local code = codeEditor:GetText()
        if code and code ~= "" then
            DF.Widgets:ShowCopyDialog(code)
        end
    end)

    runBtn:SetScript("OnClick", function()
        if not activeTabId then return end
        SaveCurrent()
        if codeEditor.PushUndo then codeEditor:PushUndo() end

        local code = codeEditor:GetText()
        if not code or code == "" then return end

        DF.EventBus:Fire("DF_EXECUTE_CODE", {
            code = code,
            source = "snippet",
        })
    end)

    ---------------------------------------------------------------------------
    -- InsertText for IntegrationBus
    ---------------------------------------------------------------------------
    function editor:InsertText(text)
        if activeTabId then
            -- Append to current snippet
            local current = codeEditor:GetText() or ""
            if current ~= "" and not current:match("\n$") then
                current = current .. "\n"
            end
            codeEditor:SetText(current .. text)
        else
            -- No snippet open; create one
            self:CreateAndInsert(text)
        end
    end

    function editor:CreateAndInsert(text)
        SaveCurrent()
        local snippet = DF.SnippetStore:Create("Untitled")
        snippetList:Refresh()
        OpenTab(snippet.id)
        codeEditor:SetText(text)
    end

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    function editor:OnFirstActivate()
        DF.SnippetStore:Init()
        snippetList:Refresh()

        -- Restore sidebar tab preference
        local tab = DevForgeDB and DevForgeDB.snippetSidebarTab or "snippets"
        SetSidebarTab(tab)

        -- Restore previously open tabs
        local savedTabs = (DevForgeDB and DevForgeDB.openSnippetTabs) or {}
        for _, id in ipairs(savedTabs) do
            if DF.SnippetStore:Get(id) then
                openTabs[#openTabs + 1] = id
            end
        end

        local lastId = DevForgeDB and DevForgeDB.lastSnippetId
        local lastSnippet = lastId and DF.SnippetStore:Get(lastId)
        if lastSnippet and not lastSnippet.isProject then
            OpenTab(lastId)
        elseif openTabs[1] then
            OpenTab(openTabs[1])
        else
            SelectNext()
        end
    end

    function editor:OnActivate()
        snippetList:Refresh()
        PurgeMissingTabs()
    end

    function editor:OnDeactivate()
        SaveCurrent()
        if DevForgeDB and activeTabId then
            DevForgeDB.lastSnippetId = activeTabId
        end
        codeEditor:ClearFocus()
        nameInput:ClearFocus()
    end

    editor.sidebar = sidebarFrame
    editor.editor = editorFrame
    return editor
end, "Editor")
