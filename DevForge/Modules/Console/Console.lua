local _, DF = ...

-- Register the Console module
-- Console has dual-mode: full REPL when active (takes over editor+bottom), and
-- the bottom panel REPL always available regardless of active module.
DF.ModuleSystem:Register("Console", function(sidebarParent, editorParent)
    local contentParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not contentParent then
        error("No content parent available")
    end

    local console = {}

    -- The Console module does NOT use the normal editor/sidebar split.
    -- When Console is active, the bottom panel expands to fill the entire main area.
    -- We create a minimal editor frame that just shows a message directing to the bottom panel.

    -- Editor frame (shown when Console is active, but the bottom panel takes over)
    local editorFrame = CreateFrame("Frame", nil, contentParent)
    editorFrame:SetAllPoints(contentParent)

    -- Toolbar (top strip within the expanded bottom panel area)
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 4)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local clearBtn = DF.Widgets:CreateButton(toolbar, "Clear", 55)
    clearBtn:SetPoint("LEFT", 2, 0)

    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 55)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)

    -- The Console's "editor frame" just contains the toolbar.
    -- The actual output and input are in the BottomPanel, which takes over main area.

    console.editor = editorFrame
    console.frame = editorFrame -- Legacy compatibility

    -- Initialize history
    DF.ConsoleHistory:Init()

    -- Welcome message in the shared output
    local welcomeShown = false

    clearBtn:SetScript("OnClick", function()
        if DF.bottomPanel then
            DF.bottomPanel:ClearOutput()
        end
    end)

    copyBtn:SetScript("OnClick", function()
        if DF.bottomPanel then
            local text = DF.bottomPanel:GetSharedOutput():GetText()
            if text and text ~= "" then
                DF.Widgets:ShowCopyDialog(text)
            end
        end
    end)

    -- Public API for slash command execution
    function console:ExecuteCode(code)
        if not code or code == "" then return end

        -- Ensure output goes to shared bottom panel output
        local bp = DF.bottomPanel
        if not bp then return end

        local output = bp:GetSharedOutput()
        if not output then return end

        DF.ConsoleHistory:Add(code)

        output:AddLine(DF.Colors.func .. "> |r" .. DF.Colors.text .. code .. "|r")

        local result = DF.ConsoleExec:Execute(code)
        local lines = DF.ConsoleExec:FormatResults(result)
        if #lines > 0 then
            output:AddLines(lines)
        end
        output:AddLine("")

        -- Ensure bottom panel shows output tab
        bp:SelectTab("output")
    end

    -- InsertText support for IntegrationBus
    function console:InsertText(text)
        if DF.bottomPanel then
            local input = DF.bottomPanel:GetInputLine()
            if input then
                input:SetText(text)
                input:Focus()
            end
        end
    end

    function console:OnActivate()
        -- When Console activates, the bottom panel expands to fill the main area
        -- (handled by MainWindow:UpdateLayout via MODULE_ACTIVATED event)
        if DF.bottomPanel then
            DF.bottomPanel:SelectTab("output")
            local input = DF.bottomPanel:GetInputLine()
            if input then
                input:Focus()
            end
        end

        if not welcomeShown and DF.bottomPanel then
            welcomeShown = true
            local output = DF.bottomPanel:GetSharedOutput()
            -- Only add welcome if output is nearly empty
            if output and #output.lines <= 3 then
                output:AddLine(DF.Colors.func .. "DevForge Console v" .. DF.ADDON_VERSION .. "|r")
                output:AddLine(DF.Colors.dim .. "Type Lua code and press Enter to execute. Shift+Enter for newline.|r")
                output:AddLine(DF.Colors.dim .. "Up/Down arrows cycle command history. Execution is tainted (like /run).|r")
                output:AddLine("")
            end
        end
    end

    function console:OnDeactivate()
        -- Bottom panel returns to normal size (handled by MainWindow:UpdateLayout)
        if DF.bottomPanel then
            local input = DF.bottomPanel:GetInputLine()
            if input then
                input:ClearFocus()
            end
        end
    end

    -- Return as legacy single-frame module
    -- The Console doesn't have a sidebar component
    return console
end, "Console")
