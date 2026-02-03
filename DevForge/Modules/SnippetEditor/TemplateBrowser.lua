local _, DF = ...

DF.TemplateBrowser = {}

local Browser = DF.TemplateBrowser

function Browser:Create(parent)
    local container = CreateFrame("Frame", nil, parent)

    local browser = {
        frame = container,
        onInsert = nil,
        selectedTemplate = nil,
    }

    ---------------------------------------------------------------------------
    -- Top half: search + tree
    ---------------------------------------------------------------------------
    local topHalf = CreateFrame("Frame", nil, container)
    topHalf:SetPoint("TOPLEFT", 0, 0)
    topHalf:SetPoint("RIGHT", 0, 0)
    topHalf:SetHeight(10) -- will be adjusted by split

    local searchBox = DF.Widgets:CreateSearchBox(container, "Search templates...", 24)
    searchBox.frame:SetPoint("TOPLEFT", topHalf, 0, 0)
    searchBox.frame:SetPoint("TOPRIGHT", topHalf, 0, 0)

    local treeView = DF.Widgets:CreateTreeView(container)
    treeView.frame:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", 0, -2)
    treeView.frame:SetPoint("BOTTOMRIGHT", topHalf, "BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------------------
    -- Bottom half: detail / preview panel
    ---------------------------------------------------------------------------
    local detailPanel = CreateFrame("Frame", nil, container, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(detailPanel, true)

    -- Hint shown when nothing is selected
    local hintText = detailPanel:CreateFontString(nil, "OVERLAY")
    hintText:SetFontObject(DF.Theme:UIFont())
    hintText:SetPoint("CENTER", 0, 0)
    hintText:SetText("Click a template to preview")
    hintText:SetTextColor(0.45, 0.45, 0.45, 1)

    -- Detail content (hidden until a template is selected)
    local detailContent = CreateFrame("Frame", nil, detailPanel)
    detailContent:SetPoint("TOPLEFT", 6, -6)
    detailContent:SetPoint("BOTTOMRIGHT", -6, 6)
    detailContent:Hide()

    -- Template name
    local nameText = detailContent:CreateFontString(nil, "OVERLAY")
    nameText:SetFontObject(DF.Theme:UIFont())
    nameText:SetPoint("TOPLEFT", 0, 0)
    nameText:SetPoint("TOPRIGHT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(0.6, 0.75, 1, 1)

    -- Description
    local descText = detailContent:CreateFontString(nil, "OVERLAY")
    descText:SetFontObject(DF.Theme:UIFont())
    descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    descText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -3)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Placeholder fields container (below description, above buttons)
    local fieldsFrame = CreateFrame("Frame", nil, detailContent)
    fieldsFrame:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -4)
    fieldsFrame:SetPoint("TOPRIGHT", descText, "BOTTOMRIGHT", 0, -4)

    -- Insert button (anchored at bottom of detail panel)
    local insertBtn = DF.Widgets:CreateButton(detailContent, "Insert", 60)
    insertBtn:SetPoint("BOTTOMLEFT", 0, 0)

    local copyBtn = DF.Widgets:CreateButton(detailContent, "Copy", 50)
    copyBtn:SetPoint("LEFT", insertBtn, "RIGHT", 4, 0)

    -- Placeholder row pool
    local fieldRows = {}

    local function ClearFields()
        for _, row in ipairs(fieldRows) do
            row.frame:Hide()
        end
    end

    local function GetFieldRow(index)
        if fieldRows[index] then
            fieldRows[index].frame:Show()
            return fieldRows[index]
        end

        local row = CreateFrame("Frame", nil, fieldsFrame)
        row:SetHeight(20)

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetPoint("LEFT", 0, 0)
        label:SetTextColor(0.55, 0.55, 0.55, 1)
        label:SetJustifyH("LEFT")

        local input = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        input:SetPoint("LEFT", row, "LEFT", 70, 0)
        input:SetPoint("RIGHT", 0, 0)
        input:SetHeight(18)
        input:SetAutoFocus(false)
        input:SetFontObject(DF.Theme:UIFont())
        input:SetTextColor(0.83, 0.83, 0.83, 1)
        input:SetMaxLetters(200)
        DF.Theme:ApplyInputStyle(input)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local entry = { frame = row, label = label, input = input, token = nil }
        fieldRows[index] = entry
        return entry
    end

    ---------------------------------------------------------------------------
    -- Show template detail
    ---------------------------------------------------------------------------
    local function ShowDetail(template)
        if not template then
            detailContent:Hide()
            hintText:Show()
            browser.selectedTemplate = nil
            return
        end

        browser.selectedTemplate = template
        hintText:Hide()
        detailContent:Show()

        nameText:SetText(template.name or "")
        descText:SetText(template.desc or "")

        -- Build placeholder fields
        ClearFields()
        local placeholders = template.placeholders or {}
        local yOff = 0
        for i, ph in ipairs(placeholders) do
            local row = GetFieldRow(i)
            row.token = ph.token
            row.label:SetText(ph.label)
            row.input:SetText(ph.default or "")
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", fieldsFrame, "TOPLEFT", 0, -yOff)
            row.frame:SetPoint("TOPRIGHT", fieldsFrame, "TOPRIGHT", 0, -yOff)
            yOff = yOff + 22
        end
        fieldsFrame:SetHeight(math.max(yOff, 1))
    end

    -- Resolve placeholders and return final code
    local function GetResolvedCode()
        local template = browser.selectedTemplate
        if not template then return nil end
        local code = template.code or ""
        local placeholders = template.placeholders or {}
        for i, ph in ipairs(placeholders) do
            local row = fieldRows[i]
            if row then
                local value = row.input:GetText() or ph.default or ""
                code = code:gsub("%$" .. ph.token, value)
            end
        end
        return code
    end

    ---------------------------------------------------------------------------
    -- Button handlers
    ---------------------------------------------------------------------------
    insertBtn:SetScript("OnClick", function()
        local code = GetResolvedCode()
        if code and browser.onInsert then
            local name = browser.selectedTemplate and browser.selectedTemplate.name or "Template"
            browser.onInsert(code, name)
        end
    end)

    copyBtn:SetScript("OnClick", function()
        local code = GetResolvedCode()
        if code and code ~= "" then
            DF.Widgets:ShowCopyDialog(code)
        end
    end)

    ---------------------------------------------------------------------------
    -- Split layout: tree takes top ~55%, detail takes bottom ~45%
    ---------------------------------------------------------------------------
    local SPLIT_RATIO = 0.55

    local function UpdateLayout()
        local h = container:GetHeight()
        if h <= 0 then return end
        local topH = math.floor(h * SPLIT_RATIO)
        topHalf:SetHeight(topH)
        detailPanel:ClearAllPoints()
        detailPanel:SetPoint("TOPLEFT", topHalf, "BOTTOMLEFT", 0, -2)
        detailPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end

    container:SetScript("OnSizeChanged", function()
        C_Timer.After(0, UpdateLayout)
    end)

    ---------------------------------------------------------------------------
    -- Tree setup
    ---------------------------------------------------------------------------
    local function BuildNodes(filter)
        local nodes = {}
        local catData = DF.SnippetTemplates
        if not catData then return nodes end

        local filterLower = filter and filter:lower() or nil

        for _, catName in ipairs(catData.categories) do
            local children = {}
            for _, tmpl in ipairs(catData.templates) do
                if tmpl.category == catName then
                    local match = true
                    if filterLower and filterLower ~= "" then
                        local nameMatch = tmpl.name and tmpl.name:lower():find(filterLower, 1, true)
                        local descMatch = tmpl.desc and tmpl.desc:lower():find(filterLower, 1, true)
                        match = nameMatch or descMatch
                    end
                    if match then
                        children[#children + 1] = {
                            id = "tmpl_" .. tmpl.id,
                            text = tmpl.name,
                            data = tmpl,
                        }
                    end
                end
            end
            if #children > 0 then
                nodes[#nodes + 1] = {
                    id = "cat_" .. catName,
                    text = catName,
                    children = children,
                }
            end
        end
        return nodes
    end

    local function RefreshTree(filter)
        local nodes = BuildNodes(filter)
        treeView:SetNodes(nodes)
        treeView:ExpandAll()
    end

    RefreshTree(nil)

    searchBox:SetOnSearch(function(text)
        RefreshTree(text)
        ShowDetail(nil) -- clear preview when search changes
    end)

    -- Click a leaf node → preview it in the detail panel
    treeView:SetOnSelect(function(node)
        if node.data then
            ShowDetail(node.data)
        end
    end)

    ---------------------------------------------------------------------------
    -- Public API
    ---------------------------------------------------------------------------
    function browser:SetOnInsert(callback)
        self.onInsert = callback
    end

    -- Legacy compat: SetOnSelect maps to SetOnInsert
    function browser:SetOnSelect(callback)
        self.onInsert = callback
    end

    function browser:Refresh()
        RefreshTree(searchBox:GetText())
    end

    return browser
end
