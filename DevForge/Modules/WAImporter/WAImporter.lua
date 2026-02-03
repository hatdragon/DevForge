local _, DF = ...

DF.WAImporter = {}

local WAImporter = DF.WAImporter

local dialog = nil

---------------------------------------------------------------------------
-- Local UI helpers (same patterns as AddonScaffold)
---------------------------------------------------------------------------

local function CreateTextInput(parent, labelText, defaultText, width, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(DF.Theme:UIFont())
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.65, 0.65, 0.65, 1)
    label:SetWidth(80)
    label:SetJustifyH("RIGHT")

    local input = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    input:SetPoint("LEFT", label, "RIGHT", 4, 0)
    input:SetSize(width or 180, 20)
    input:SetAutoFocus(false)
    input:SetFontObject(DF.Theme:UIFont())
    input:SetTextColor(0.83, 0.83, 0.83, 1)
    input:SetMaxLetters(200)
    input:SetText(defaultText or "")
    DF.Theme:ApplyInputStyle(input)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnTextChanged", function(self, userInput)
        if userInput and onChange then onChange(self:GetText()) end
    end)

    local wrapper = { frame = row, input = input }
    function wrapper:GetText() return input:GetText() or "" end
    function wrapper:SetText(t) input:SetText(t or "") end
    return wrapper
end

local function CreateFileSelector(parent, files, default, onChange)
    local btn = DF.Widgets:CreateButton(parent, default or files[1], 130)
    local current = default or files[1]
    local fileList = files
    local menu = DF.Widgets:CreateDropDown()

    btn:SetScript("OnClick", function(self)
        local menuItems = {}
        for _, file in ipairs(fileList) do
            menuItems[#menuItems + 1] = {
                text = file,
                func = function()
                    current = file
                    btn:SetLabel(file)
                    if onChange then onChange(file) end
                end,
            }
        end
        menu:Show(self, menuItems)
    end)

    local selector = { button = btn }
    function selector:GetValue() return current end
    function selector:SetFiles(newFiles, newDefault)
        fileList = newFiles
        current = newDefault or newFiles[1]
        btn:SetLabel(current)
    end
    return selector
end

---------------------------------------------------------------------------
-- Dialog creation (singleton)
---------------------------------------------------------------------------

local function GetDialog()
    if dialog then return dialog end

    local frame = CreateFrame("Frame", "DevForgeWAImporter", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetSize(480, 520)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    DF.Theme:ApplyDialogChrome(frame)
    tinsert(UISpecialFrames, "DevForgeWAImporter")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", 12, -12)
    titleBar:SetPoint("TOPRIGHT", -12, -12)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then frame:StartMoving() end
    end)
    titleBar:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFontObject(DF.Theme:UIFont())
    titleText:SetPoint("LEFT", 4, 0)
    titleText:SetText("WeakAuras Import")
    titleText:SetTextColor(0.6, 0.75, 1, 1)

    -- State
    local state = {
        importString = "",
        decoded = nil,
        analysis = nil,
        projectName = "",
        error = nil,
        currentFile = nil,
    }

    local projectCallback = nil
    local codePreview = nil
    local fileSelector = nil
    local generatedFiles = nil

    ---------------------------------------------------------------------------
    -- Layout: everything parented to frame, using yOff accumulator
    -- (same pattern as AddonScaffold)
    ---------------------------------------------------------------------------
    local LEFT = 12
    local RIGHT = -12
    local yOff = -42  -- below title bar

    -- "Paste WA export string:" label
    local importLabel = frame:CreateFontString(nil, "OVERLAY")
    importLabel:SetFontObject(DF.Theme:UIFont())
    importLabel:SetPoint("TOPLEFT", LEFT + 4, yOff)
    importLabel:SetText("Paste WA export string:")
    importLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    yOff = yOff - 16

    -- Import editbox
    local importBox = DF.Widgets:CreateCodeEditBox(frame, { multiLine = true, readOnly = false })
    importBox.frame:SetPoint("TOPLEFT", LEFT, yOff)
    importBox.frame:SetPoint("RIGHT", frame, "RIGHT", RIGHT, 0)
    importBox.frame:SetHeight(100)
    yOff = yOff - 104

    importBox:SetOnTextChanged(function()
        state.importString = importBox:GetText() or ""
    end)

    -- Error text
    local errorText = frame:CreateFontString(nil, "OVERLAY")
    errorText:SetFontObject(DF.Theme:UIFont())
    errorText:SetPoint("TOPLEFT", LEFT + 4, yOff)
    errorText:SetPoint("RIGHT", frame, "RIGHT", RIGHT - 4, 0)
    errorText:SetTextColor(1, 0.3, 0.3, 1)
    errorText:SetText("")
    errorText:SetJustifyH("LEFT")
    errorText:SetWordWrap(true)

    -- Decode button
    local decodeBtn = DF.Widgets:CreateButton(frame, "Decode", 70)
    decodeBtn:SetPoint("TOPLEFT", LEFT, yOff - 16)
    yOff = yOff - 16 - DF.Layout.buttonHeight - 6

    -- Info panel (shown after decode)
    local infoPanel = CreateFrame("Frame", nil, frame)
    infoPanel:SetPoint("TOPLEFT", LEFT, yOff)
    infoPanel:SetPoint("RIGHT", frame, "RIGHT", RIGHT, 0)
    infoPanel:SetHeight(50)
    infoPanel:Hide()

    local infoName = infoPanel:CreateFontString(nil, "OVERLAY")
    infoName:SetFontObject(DF.Theme:UIFont())
    infoName:SetPoint("TOPLEFT", 4, 0)
    infoName:SetTextColor(0.83, 0.83, 0.83, 1)
    infoName:SetText("")

    local infoDetails = infoPanel:CreateFontString(nil, "OVERLAY")
    infoDetails:SetFontObject(DF.Theme:UIFont())
    infoDetails:SetPoint("TOPLEFT", infoName, "BOTTOMLEFT", 0, -2)
    infoDetails:SetPoint("RIGHT", infoPanel, "RIGHT", -4, 0)
    infoDetails:SetTextColor(0.5, 0.5, 0.5, 1)
    infoDetails:SetText("")
    infoDetails:SetWordWrap(true)
    infoDetails:SetJustifyH("LEFT")
    -- yOff adjusted dynamically when info panel shows

    -- Project name input (hidden until decode)
    local projectNameInput = CreateTextInput(frame, "Project:", "", 200, function(val)
        state.projectName = val
    end)
    projectNameInput.frame:SetPoint("TOPLEFT", infoPanel, "BOTTOMLEFT", 0, -4)
    projectNameInput.frame:SetPoint("RIGHT", frame, "RIGHT", RIGHT, 0)
    projectNameInput.frame:Hide()

    -- File selector row (hidden until decode)
    local fileSelectorRow = CreateFrame("Frame", nil, frame)
    fileSelectorRow:SetHeight(24)
    fileSelectorRow:SetPoint("TOPLEFT", projectNameInput.frame, "BOTTOMLEFT", 0, -4)
    fileSelectorRow:SetPoint("RIGHT", frame, "RIGHT", RIGHT, 0)
    fileSelectorRow:Hide()

    local fileLabel = fileSelectorRow:CreateFontString(nil, "OVERLAY")
    fileLabel:SetFontObject(DF.Theme:UIFont())
    fileLabel:SetPoint("LEFT", 4, 0)
    fileLabel:SetText("Preview:")
    fileLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    fileSelector = CreateFileSelector(fileSelectorRow, { "TOC", "Init.lua" }, "TOC", function(file)
        state.currentFile = file
        if codePreview and generatedFiles then
            for _, f in ipairs(generatedFiles) do
                if f.name == file or (file == "TOC" and f.name:match("%.toc$")) then
                    codePreview:SetText(f.code)
                    break
                end
            end
        end
    end)
    fileSelector.button:SetPoint("LEFT", fileLabel, "RIGHT", 4, 0)

    -- Code preview (hidden until decode)
    codePreview = DF.Widgets:CreateCodeEditBox(frame, { multiLine = true, readOnly = true })
    codePreview.frame:SetPoint("TOPLEFT", fileSelectorRow, "BOTTOMLEFT", 0, -2)
    codePreview.frame:SetPoint("BOTTOMRIGHT", RIGHT, 40)
    codePreview.frame:Hide()

    ---------------------------------------------------------------------------
    -- Decode logic
    ---------------------------------------------------------------------------

    local function SanitizeProjectName(name)
        if not name or name == "" then return "WAImport" end
        local clean = name:gsub("[^%w_ ]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "")
        if clean == "" then return "WAImport" end
        return clean
    end

    local function BuildInfoText(analysis)
        local parts = {}

        if analysis.isGroup then
            parts[#parts + 1] = "Group: " .. (analysis.groupId or "Unknown")
            parts[#parts + 1] = "Children: " .. #analysis.auras
        else
            local a = analysis.auras[1]
            if a then
                parts[#parts + 1] = "Type: " .. (a.regionType or "unknown")
            end
        end

        for i, aura in ipairs(analysis.auras) do
            local trigDesc = {}
            for _, trig in ipairs(aura.triggers or {}) do
                local desc = trig.type or "unknown"
                if trig.type == "aura2" then
                    if trig.auranames and #trig.auranames > 0 then
                        desc = "aura: " .. trig.auranames[1]
                    elseif trig.auraspellids and #trig.auraspellids > 0 then
                        desc = "aura ID: " .. tostring(trig.auraspellids[1])
                    end
                elseif trig.type == "status" then
                    desc = trig.event or "status"
                end
                trigDesc[#trigDesc + 1] = desc
            end
            if #trigDesc > 0 then
                local label = aura.id or ("Aura " .. i)
                parts[#parts + 1] = label .. " triggers: " .. table.concat(trigDesc, ", ")
            end
        end

        return table.concat(parts, "\n")
    end

    local function OnDecode()
        -- Reset post-decode state
        state.decoded = nil
        state.analysis = nil
        state.error = nil
        generatedFiles = nil
        errorText:SetText("")
        infoPanel:Hide()
        projectNameInput.frame:Hide()
        fileSelectorRow:Hide()
        codePreview.frame:Hide()

        local str = state.importString
        if not str or str:match("^%s*$") then
            errorText:SetText("Paste a WeakAuras export string above.")
            return
        end

        -- Decode
        local success, data, err = DF.WADecode:Decode(str)
        if not success then
            state.error = err
            errorText:SetText(err or "Unknown decode error")
            return
        end

        state.decoded = data

        -- Analyze
        local analysis, analyzeErr = DF.WADecode:Analyze(data)
        if not analysis then
            state.error = analyzeErr
            errorText:SetText(analyzeErr or "Unknown analysis error")
            return
        end

        state.analysis = analysis

        -- Populate info panel
        local auraName = analysis.groupId or (analysis.auras[1] and analysis.auras[1].id) or "WAImport"
        infoName:SetText(auraName)
        infoDetails:SetText(BuildInfoText(analysis))
        infoPanel:Show()

        -- Set project name
        local defaultName = SanitizeProjectName(auraName)
        state.projectName = defaultName
        projectNameInput:SetText(defaultName)
        projectNameInput.frame:Show()

        -- Generate code
        generatedFiles = DF.WACodeGen:Generate(analysis, defaultName)
        if not generatedFiles then
            errorText:SetText("Code generation failed")
            return
        end

        -- Setup file selector
        local fileNames = {}
        for _, f in ipairs(generatedFiles) do
            fileNames[#fileNames + 1] = f.name
        end
        fileSelector:SetFiles(fileNames, fileNames[1])
        state.currentFile = fileNames[1]
        fileSelectorRow:Show()

        -- Show preview
        codePreview:SetText(generatedFiles[1].code)
        codePreview.frame:Show()
    end

    decodeBtn:SetScript("OnClick", OnDecode)

    ---------------------------------------------------------------------------
    -- Bottom buttons
    ---------------------------------------------------------------------------
    local cancelBtn = DF.Widgets:CreateButton(frame, "Cancel", 60)
    cancelBtn:SetPoint("BOTTOMRIGHT", RIGHT, 12)
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)

    local createProjectBtn = DF.Widgets:CreateButton(frame, "Create Project", 105)
    createProjectBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -4, 0)
    createProjectBtn:SetScript("OnClick", function()
        if not projectCallback then return end
        if not generatedFiles then return end

        local name = state.projectName ~= "" and state.projectName or "WAImport"
        local files = DF.WACodeGen:Generate(state.analysis, name)
        if not files then return end

        projectCallback(files, name)
        frame:Hide()
    end)

    local copyAllBtn = DF.Widgets:CreateButton(frame, "Copy All Files", 100)
    copyAllBtn:SetPoint("RIGHT", createProjectBtn, "LEFT", -4, 0)
    copyAllBtn:SetScript("OnClick", function()
        if not state.analysis then return end
        local name = state.projectName ~= "" and state.projectName or "WAImport"
        local allCode = DF.WACodeGen:GenerateAllFilesText(state.analysis, name)
        if allCode and allCode ~= "" then
            DF.Widgets:ShowCopyDialog(allCode)
        end
    end)

    ---------------------------------------------------------------------------
    -- Reset helper
    ---------------------------------------------------------------------------
    local function ResetDialog()
        state.importString = ""
        state.decoded = nil
        state.analysis = nil
        state.projectName = ""
        state.error = nil
        state.currentFile = nil
        generatedFiles = nil

        importBox:SetText("")
        errorText:SetText("")
        infoName:SetText("")
        infoDetails:SetText("")
        infoPanel:Hide()
        projectNameInput:SetText("")
        projectNameInput.frame:Hide()
        fileSelectorRow:Hide()
        codePreview:SetText("")
        codePreview.frame:Hide()
    end

    dialog = {
        frame = frame,
        state = state,
        setProjectCallback = function(self, cb) projectCallback = cb end,
        reset = ResetDialog,
    }

    return dialog
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function WAImporter:Show(callback)
    local d = GetDialog()
    d:setProjectCallback(callback)
    d:reset()
    d.frame:Show()
end
