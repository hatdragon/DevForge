local _, DF = ...

-- Register the Error Handler module with sidebar + editor split
DF.ModuleSystem:Register("ErrorHandler", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local monitor = {}

    ---------------------------------------------------------------------------
    -- Sidebar: error list
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    local errorList = DF.ErrorList:Create(sidebarFrame)
    errorList.frame:SetAllPoints(sidebarFrame)

    ---------------------------------------------------------------------------
    -- Editor: toolbar + error detail
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local clearBtn = DF.Widgets:CreateButton(toolbar, "Clear All", 70)
    clearBtn:SetPoint("LEFT", 2, 0)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 55)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)

    local pauseBtn = DF.Widgets:CreateButton(toolbar, "Pause", 60)
    pauseBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)

    local toConsoleBtn = DF.Widgets:CreateButton(toolbar, "To Console", 80)
    toConsoleBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 8, 0)

    -- Count label
    local countLabel = toolbar:CreateFontString(nil, "OVERLAY")
    countLabel:SetFontObject(DF.Theme:UIFont())
    countLabel:SetPoint("RIGHT", -4, 0)
    countLabel:SetTextColor(0.6, 0.6, 0.6, 1)

    local function UpdateCount()
        local n = DF.ErrorHandler:GetCount()
        countLabel:SetText(n .. " error" .. (n == 1 and "" or "s"))
    end

    -- Error detail (main area)
    local errorDetail = DF.ErrorDetail:Create(editorFrame)
    errorDetail.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    errorDetail.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Wire up selection
    errorList:SetOnSelect(function(id)
        local err = DF.ErrorHandler:GetError(id)
        errorDetail:ShowError(err)
    end)

    -- Copy button
    copyBtn:SetScript("OnClick", function()
        local text = errorDetail:GetText()
        if text and text ~= "" then
            DF.Widgets:ShowCopyDialog(text)
        end
    end)

    -- Clear button
    clearBtn:SetScript("OnClick", function()
        DF.ErrorHandler:Clear()
        errorList:Refresh()
        errorDetail:Clear()
        UpdateCount()
    end)

    -- Pause/Resume button
    pauseBtn:SetScript("OnClick", function()
        local isPaused = DF.ErrorHandler:IsPaused()
        DF.ErrorHandler:SetPaused(not isPaused)
        if not isPaused then
            pauseBtn:SetText("Resume")
        else
            pauseBtn:SetText("Pause")
        end
    end)

    -- Copy to Console button
    toConsoleBtn:SetScript("OnClick", function()
        local text = errorDetail:GetText()
        if text and text ~= "" then
            -- Put error context into the REPL input
            if DF.bottomPanel then
                local input = DF.bottomPanel:GetInputLine()
                if input then
                    -- Extract just the error message for the input
                    local errMsg = text:match("%[ERROR%] (.-)\n") or text:match("%[WARNING%] (.-)\n") or text:sub(1, 200)
                    input:SetText("-- Error: " .. errMsg)
                    input:Focus()
                end
                DF.bottomPanel:SelectTab("output")
            end
        end
    end)

    -- Live update callback via EventBus (set up by BottomPanel)
    DF.EventBus:On("DF_ERROR_RECEIVED", function(err, isDuplicate)
        errorList:Refresh()
        UpdateCount()
        if isDuplicate and errorDetail.currentId == err.id then
            errorDetail:ShowError(err)
        end
    end, "ErrorMonitor")

    function monitor:OnFirstActivate()
        DF.ErrorHandler:Init()
        errorList:Refresh()
        UpdateCount()
    end

    function monitor:OnActivate()
        errorList:Refresh()
        UpdateCount()
    end

    function monitor:OnDeactivate()
        -- nothing special
    end

    monitor.sidebar = sidebarFrame
    monitor.editor = editorFrame
    return monitor
end, "Errors")
