local _, DF = ...

DF.ModuleSystem:Register("TableViewer", function(sidebarParent, editorParent)
    editorParent = editorParent or DF.ModuleSystem:GetContentParent()
    if not editorParent then
        error("No content parent available")
    end

    local viewer = {}
    local knownTablesScanned = false

    ---------------------------------------------------------------------------
    -- Sidebar: search box + known tables tree
    ---------------------------------------------------------------------------
    local sidebarFrame = CreateFrame("Frame", nil, sidebarParent or editorParent)
    if sidebarParent then
        sidebarFrame:SetAllPoints(sidebarParent)
    end

    -- Search box at top of sidebar
    local searchBox = DF.Widgets:CreateSearchBox(sidebarFrame, "Filter tables...", 24)
    searchBox.frame:SetPoint("TOPLEFT", 4, -4)
    searchBox.frame:SetPoint("TOPRIGHT", -4, -4)

    -- Known tables tree below search
    local sidebarTree = DF.Widgets:CreateTreeView(sidebarFrame)
    sidebarTree.frame:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", -4, -4)
    sidebarTree.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- All known table nodes (unfiltered)
    local allKnownNodes = {}

    -- Filter sidebar tree by search text
    local function FilterSidebarNodes(query)
        if not query or query == "" then
            sidebarTree:SetNodes(allKnownNodes)
            return
        end

        local lowerQuery = query:lower()
        local filtered = {}

        for _, category in ipairs(allKnownNodes) do
            if category.children then
                local matchingChildren = {}
                for _, child in ipairs(category.children) do
                    if child.text:lower():find(lowerQuery, 1, true) then
                        matchingChildren[#matchingChildren + 1] = child
                    end
                end
                if #matchingChildren > 0 then
                    filtered[#filtered + 1] = {
                        id = category.id .. ".filtered",
                        text = category.text:match("^(.-)%s*%(") .. " (" .. #matchingChildren .. ")",
                        children = matchingChildren,
                    }
                end
            end
        end

        sidebarTree:SetNodes(filtered)
        for _, node in ipairs(filtered) do
            sidebarTree:ExpandNode(node.id)
        end
    end

    searchBox:SetOnSearch(FilterSidebarNodes)

    ---------------------------------------------------------------------------
    -- Editor: toolbar (expression input + Dump btn + status) + result tree
    ---------------------------------------------------------------------------
    local editorFrame = CreateFrame("Frame", nil, editorParent)
    editorFrame:SetAllPoints(editorParent)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, editorFrame)
    toolbar:SetHeight(DF.Layout.buttonHeight + 8)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    -- Expression input
    local inputFrame = CreateFrame("EditBox", nil, toolbar, "BackdropTemplate")
    inputFrame:SetHeight(DF.Layout.buttonHeight)
    inputFrame:SetPoint("LEFT", 4, 0)
    inputFrame:SetPoint("RIGHT", toolbar, "RIGHT", -220, 0)
    inputFrame:SetAutoFocus(false)
    inputFrame:SetMaxLetters(500)
    DF.Theme:ApplyInputStyle(inputFrame)

    -- Placeholder text for the input
    local inputPlaceholder = inputFrame:CreateFontString(nil, "OVERLAY")
    inputPlaceholder:SetFontObject(DF.Theme:UIFont())
    inputPlaceholder:SetPoint("LEFT", 6, 0)
    inputPlaceholder:SetText("Enum.ItemQuality, C_Map, _G, ...")
    inputPlaceholder:SetTextColor(0.5, 0.5, 0.5, 1)

    inputFrame:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text and text ~= "" then
            inputPlaceholder:Hide()
        else
            inputPlaceholder:Show()
        end
    end)

    inputFrame:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Dump button
    local dumpBtn = DF.Widgets:CreateButton(toolbar, "Dump", 60)
    dumpBtn:SetPoint("LEFT", inputFrame, "RIGHT", 4, 0)

    -- Copy state
    local lastDumpNodes = nil
    local statusRawText = ""

    -- Copy button
    local copyBtn = DF.Widgets:CreateButton(toolbar, "Copy", 55)
    copyBtn:SetPoint("LEFT", dumpBtn, "RIGHT", 4, 0)
    copyBtn:SetScript("OnClick", function()
        if lastDumpNodes and #lastDumpNodes > 0 then
            local lines = DF.TableDump:SerializeNodes(lastDumpNodes)
            DF.Widgets:ShowCopyDialog(table.concat(lines, "\n"))
        elseif statusRawText ~= "" then
            DF.Widgets:ShowCopyDialog(statusRawText)
        end
    end)

    -- Status label (clickable — click to copy raw text)
    local statusBtn = CreateFrame("Button", nil, toolbar)
    statusBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
    statusBtn:SetPoint("RIGHT", -4, 0)
    statusBtn:SetHeight(DF.Layout.buttonHeight)

    local statusLabel = statusBtn:CreateFontString(nil, "OVERLAY")
    statusLabel:SetFontObject(DF.Theme:UIFont())
    statusLabel:SetAllPoints()
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    statusLabel:SetText("")

    statusBtn:SetScript("OnClick", function()
        if statusRawText ~= "" then
            DF.Widgets:ShowCopyDialog(statusRawText)
        end
    end)
    statusBtn:SetScript("OnEnter", function(self)
        if statusRawText ~= "" then
            statusLabel:SetTextColor(0.4, 0.7, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Click to copy", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    statusBtn:SetScript("OnLeave", function()
        statusLabel:SetTextColor(0.6, 0.6, 0.6, 1)
        GameTooltip:Hide()
    end)

    local function SetStatus(displayText, rawText)
        statusLabel:SetText(displayText)
        statusRawText = rawText or DF.Util:StripColors(displayText)
    end

    -- Result tree (main dump viewer)
    local resultTree = DF.Widgets:CreateTreeView(editorFrame)
    resultTree.frame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    resultTree.frame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Click on truncated "... (X more)" node to load next batch
    resultTree:SetOnSelect(function(node)
        if node and node.data and node.data.truncated then
            if DF.TableDump:LoadMore(node) then
                resultTree:Refresh()
            end
        end
    end)

    -- Right-click any tree row to copy its text
    resultTree:SetOnRightClick(function(node)
        if node and node.text then
            DF.Widgets:ShowCopyDialog(DF.Util:StripColors(node.text))
        end
    end)

    ---------------------------------------------------------------------------
    -- Dump logic
    ---------------------------------------------------------------------------
    local function DumpExpression(expr)
        expr = DF.Util:Trim(expr)
        if expr == "" then
            SetStatus(DF.Colors.dim .. "Enter an expression to dump|r", "")
            lastDumpNodes = nil
            resultTree:SetNodes({})
            return
        end

        local value, ok, err = DF.TableDump:Resolve(expr)

        if not ok then
            SetStatus(DF.Colors.error .. err .. "|r", err)
            lastDumpNodes = nil
            resultTree:SetNodes({})
            return
        end

        if value == nil then
            SetStatus(DF.Colors.nilVal .. "nil|r", expr .. " = nil")
            local nodes = {{ id = "result.nil", text = DF.Colors.nilVal .. "nil|r" }}
            lastDumpNodes = nodes
            resultTree:SetNodes(nodes)
            return
        end

        local t = type(value)
        if t == "table" then
            local count = 0
            pcall(function()
                for _ in pairs(value) do
                    count = count + 1
                    if count > 99999 then break end
                end
            end)
            SetStatus(
                DF.Colors.text .. expr .. "|r  " .. DF.Colors.dim .. "(" .. t .. ", " .. count .. " entries)|r",
                expr .. " (" .. t .. ", " .. count .. " entries)"
            )

            local nodes = DF.TableDump:BuildNodes(value, "dump")
            lastDumpNodes = nodes
            resultTree:SetNodes(nodes)

            -- Trees start collapsed; user can expand as needed
        else
            SetStatus(
                DF.Colors.text .. expr .. "|r  " .. DF.Colors.dim .. "(" .. t .. ")|r",
                expr .. " = " .. tostring(value) .. " (" .. t .. ")"
            )
            local nodes = {{ id = "result.value", text = DF.TableDump:FormatValue(value) }}
            lastDumpNodes = nodes
            resultTree:SetNodes(nodes)
        end
    end

    -- Wire up dump triggers
    dumpBtn:SetScript("OnClick", function()
        DumpExpression(inputFrame:GetText())
    end)

    inputFrame:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        DumpExpression(self:GetText())
    end)

    -- Sidebar click -> dump the selected table
    sidebarTree:SetOnSelect(function(node)
        if node and node.data and node.data.expr then
            inputFrame:SetText(node.data.expr)
            DumpExpression(node.data.expr)
        end
    end)

    ---------------------------------------------------------------------------
    -- Lifecycle
    ---------------------------------------------------------------------------
    local function ScanKnownTables()
        allKnownNodes = DF.TableDump:ScanKnownTables()
        sidebarTree:SetNodes(allKnownNodes)
    end

    function viewer:OnFirstActivate()
        if not knownTablesScanned then
            knownTablesScanned = true
            ScanKnownTables()
        end
    end

    function viewer:OnActivate()
        -- Rescan if sidebar is empty (e.g. first load)
        if not knownTablesScanned then
            knownTablesScanned = true
            ScanKnownTables()
        end
    end

    viewer.sidebar = sidebarFrame
    viewer.editor = editorFrame
    return viewer
end, "Tables")
