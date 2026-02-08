local _, DF = ...

-- Register the Snippet Editor module with sidebar + editor split
DF.ModuleSystem:Register("SnippetEditor", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local editor = {}
    local currentSnippetId = nil
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

    local snippetList = DF.SnippetList:Create(snippetsContainer)
    snippetList.frame:SetPoint("TOPLEFT", snippetsContainer, "TOPLEFT", 0, 0)
    snippetList.frame:SetPoint("BOTTOMRIGHT", snippetsContainer, "BOTTOMRIGHT", 0, 0)

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

    local waImportBtn = DF.Widgets:CreateButton(toolbar, "WA Import", 80)
    waImportBtn:SetPoint("LEFT", scaffoldBtn, "RIGHT", 4, 0)

    local runProjectBtn = DF.Widgets:CreateButton(toolbar, "Run Project", 80)
    runProjectBtn:SetPoint("LEFT", waImportBtn, "RIGHT", 4, 0)

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

    -- Run-project warning banner
    local runBanner = CreateFrame("Frame", nil, editorFrame, "BackdropTemplate")
    runBanner:SetHeight(20)
    runBanner:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    runBanner:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)
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

    -- Code editor (uses most of remaining space)
    local codeEditor = DF.Widgets:CreateCodeEditBox(editorContent, {
        multiLine = true,
        readOnly = false,
    })
    codeEditor.frame:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -2)
    codeEditor.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Logic
    ---------------------------------------------------------------------------
    local function SaveCurrent()
        if not currentSnippetId then return end
        local name = nameInput:GetText()
        local code = codeEditor:GetText()
        DF.SnippetStore:Save(currentSnippetId, name, code)
    end

    local function LoadSnippet(id)
        if not id then
            runBanner:Hide()
            UpdateEditorContentAnchor()
            editorContent:Hide()
            emptyState:Show()
            currentSnippetId = nil
            return
        end

        local snippet = DF.SnippetStore:Get(id)
        if not snippet then
            runBanner:Hide()
            UpdateEditorContentAnchor()
            editorContent:Hide()
            emptyState:Show()
            currentSnippetId = nil
            return
        end

        -- Show banner if this snippet belongs to any previously-run project
        local snippetProjectId = snippet.isProject and snippet.id or snippet.parentId
        if snippetProjectId and ranProjects[snippetProjectId] then
            runBanner:Show()
        else
            runBanner:Hide()
        end
        UpdateEditorContentAnchor()

        emptyState:Hide()
        editorContent:Show()

        currentSnippetId = id
        nameInput:SetText(snippet.name or "")
        codeEditor:SetText(snippet.code or "")
        if codeEditor.ResetUndo then codeEditor:ResetUndo() end
        snippetList:SetSelected(id)

        if DevForgeDB then
            DevForgeDB.lastSnippetId = id
        end
    end

    local function SelectNext()
        local topLevel = DF.SnippetStore:GetTopLevel()
        if #topLevel == 0 then
            LoadSnippet(nil)
            return
        end
        -- If the first top-level item is a project, select its first child
        local first = topLevel[1]
        if first.isProject then
            local children = DF.SnippetStore:GetChildren(first.id)
            if #children > 0 then
                LoadSnippet(children[1].id)
                return
            end
        end
        LoadSnippet(first.id)
    end

    -- Insert code at the cursor position in the active editor.
    -- If nothing is open, create a new snippet with the code.
    local function InsertCode(code, snippetName)
        if currentSnippetId then
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
            LoadSnippet(snippet.id)
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
        LoadSnippet(snippet.id)
        nameInput:SetFocus()
        nameInput:HighlightText()
    end

    snippetList:SetOnSelect(function(id)
        SaveCurrent()
        LoadSnippet(id)
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
                    if currentSnippetId then
                        local cur = DF.SnippetStore:Get(currentSnippetId)
                        if not cur then
                            currentSnippetId = nil
                            SelectNext()
                        end
                    end
                    snippetList:Refresh()
                end,
            }
        else
            items[#items + 1] = {
                text = "Delete snippet",
                func = function()
                    if currentSnippetId == snippetId then
                        currentSnippetId = nil
                    end
                    DF.SnippetStore:Delete(snippetId)
                    snippetList:Refresh()
                    if not currentSnippetId then
                        SelectNext()
                    end
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
        if currentSnippetId then
            local cur = DF.SnippetStore:Get(currentSnippetId)
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
        if not currentSnippetId then return end
        SaveCurrent()
        local clone = DF.SnippetStore:Duplicate(currentSnippetId)
        if clone then
            snippetList:Refresh()
            LoadSnippet(clone.id)
        end
    end)

    delBtn:SetScript("OnClick", function()
        if not currentSnippetId then return end
        local idToDelete = currentSnippetId
        currentSnippetId = nil
        DF.SnippetStore:Delete(idToDelete)
        snippetList:Refresh()
        SelectNext()
    end)

    frameBuilderBtn:SetScript("OnClick", function()
        DF.FrameBuilder:Show(function(code, snippetName)
            InsertCode(code, snippetName)
        end)
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
                LoadSnippet(children[1].id)
            end
        end)
    end)

    waImportBtn:SetScript("OnClick", function()
        DF.WAImporter:Show(function(files, projectName)
            SaveCurrent()
            local project = DF.SnippetStore:CreateProject(projectName)
            for _, file in ipairs(files) do
                local s = DF.SnippetStore:Create(file.name, project.id)
                DF.SnippetStore:Save(s.id, s.name, file.code)
            end
            SetSidebarTab("snippets")
            snippetList:Refresh()
            local children = DF.SnippetStore:GetChildren(project.id)
            if #children > 0 then
                LoadSnippet(children[1].id)
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
        if not currentSnippetId then return end
        if not DF.ConsoleExec then return end
        SaveCurrent()

        -- Ensure bottom panel is visible and on the Output tab
        local bp = DF.bottomPanel
        if bp then
            if bp.collapsed then bp:Expand() end
            bp:SelectTab("output")
        end

        -- Determine project context
        local snippet = DF.SnippetStore:Get(currentSnippetId)
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

        -- Track frames that register for lifecycle events during execution
        -- so we can simulate them after all files are loaded
        local addonLoadedFrames = {}
        local enteringWorldFrames = {}
        local realCreateFrame = CreateFrame
        CreateFrame = function(frameType, ...)
            local frame = realCreateFrame(frameType, ...)
            local realRegisterEvent = frame.RegisterEvent
            frame.RegisterEvent = function(self, event, ...)
                if event == "ADDON_LOADED" then
                    addonLoadedFrames[#addonLoadedFrames + 1] = self
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

        -- Restore CreateFrame before firing events
        CreateFrame = realCreateFrame

        -- Simulate ADDON_LOADED for frames that registered during execution
        if #addonLoadedFrames > 0 then
            DF.EventBus:Fire("DF_OUTPUT_LINE", {
                text = "-- Firing ADDON_LOADED",
                color = DF.Colors.comment,
            })

            -- Capture print output during event handlers
            local prints = {}
            local origPrint = print
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    parts[i] = tostring(select(i, ...))
                end
                prints[#prints + 1] = table.concat(parts, "    ")
            end

            for _, frame in ipairs(addonLoadedFrames) do
                local handler = frame:GetScript("OnEvent")
                if handler then
                    local ok, err = pcall(handler, frame, "ADDON_LOADED", addonName)
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
        end

        -- Simulate PLAYER_ENTERING_WORLD for frames that registered during execution
        if #enteringWorldFrames > 0 then
            DF.EventBus:Fire("DF_OUTPUT_LINE", {
                text = "-- Firing PLAYER_ENTERING_WORLD",
                color = DF.Colors.comment,
            })

            local prints = {}
            local origPrint = print
            print = function(...)
                local parts = {}
                for i = 1, select("#", ...) do
                    parts[i] = tostring(select(i, ...))
                end
                prints[#prints + 1] = table.concat(parts, "    ")
            end

            for _, frame in ipairs(enteringWorldFrames) do
                local handler = frame:GetScript("OnEvent")
                if handler then
                    local ok, err = pcall(handler, frame, "PLAYER_ENTERING_WORLD", true, false)
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
        end

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
    end)

    copyBtn:SetScript("OnClick", function()
        local code = codeEditor:GetText()
        if code and code ~= "" then
            DF.Widgets:ShowCopyDialog(code)
        end
    end)

    runBtn:SetScript("OnClick", function(_, _, down)
        if down then return end -- ignore mouse-down, fire only on mouse-up
        if not currentSnippetId then return end
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
        if currentSnippetId then
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
        LoadSnippet(snippet.id)
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

        local lastId = DevForgeDB and DevForgeDB.lastSnippetId
        local lastSnippet = lastId and DF.SnippetStore:Get(lastId)
        if lastSnippet and not lastSnippet.isProject then
            LoadSnippet(lastId)
        else
            SelectNext()
        end
    end

    function editor:OnActivate()
        snippetList:Refresh()
    end

    function editor:OnDeactivate()
        SaveCurrent()
        if DevForgeDB and currentSnippetId then
            DevForgeDB.lastSnippetId = currentSnippetId
        end
        codeEditor:ClearFocus()
        nameInput:ClearFocus()
    end

    editor.sidebar = sidebarFrame
    editor.editor = editorFrame
    return editor
end, "Editor")
