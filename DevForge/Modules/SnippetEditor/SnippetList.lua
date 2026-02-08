local _, DF = ...

DF.SnippetList = {}

local SnipList = DF.SnippetList

local ROW_HEIGHT = DF.Layout.rowHeight

function SnipList:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)

    local list = {
        frame = pane.frame,
        pane = pane,
        rows = {},
        selectedId = nil,
        onSelect = nil,
        expanded = {},  -- projectId -> true/false
    }

    function list:GetRow(index)
        if self.rows[index] then
            self.rows[index]:Show()
            return self.rows[index]
        end

        local row = CreateFrame("Button", nil, self.pane:GetContent())
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHeight(ROW_HEIGHT)

        -- Selection highlight
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(unpack(DF.Colors.rowSelected))
        sel:Hide()
        row.sel = sel

        -- Hover highlight
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(unpack(DF.Colors.highlight))
        hl:Hide()
        row.hl = hl

        -- Toggle indicator for project rows
        local toggle = row:CreateFontString(nil, "OVERLAY")
        toggle:SetFontObject(DF.Theme:UIFont())
        toggle:SetPoint("LEFT", 4, 0)
        toggle:SetTextColor(0.5, 0.5, 0.5, 1)
        toggle:SetText("")
        toggle:Hide()
        row.toggle = toggle

        -- Name text
        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", 8, 0)
        text:SetPoint("RIGHT", -8, 0)
        text:SetWordWrap(false)
        text:SetTextColor(0.83, 0.83, 0.83, 1)
        row.text = text

        row:SetScript("OnEnter", function(self)
            if self.snippetId ~= list.selectedId then
                self.hl:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if list.onRightClick then
                    list.onRightClick(self.snippetId, self.isProjectRow)
                end
                return
            end
            if self.isProjectRow then
                -- Toggle expand/collapse
                local id = self.snippetId
                list.expanded[id] = not list.expanded[id]
                list:Refresh()
            elseif self.snippetId and list.onSelect then
                list.selectedId = self.snippetId
                list:UpdateSelection()
                list.onSelect(self.snippetId)
            end
        end)

        self.rows[index] = row
        return row
    end

    function list:HideAllRows()
        for _, row in ipairs(self.rows) do
            row:Hide()
        end
    end

    -- Configure a row as a project header
    local function SetupProjectRow(row, snippet, isExpanded)
        row.isProjectRow = true
        row.toggle:Show()
        row.toggle:SetText(isExpanded and "[-]" or "[+]")
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.toggle, "RIGHT", 2, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetText(snippet.name or "Untitled")
        row.text:SetTextColor(0.55, 0.65, 0.8, 1)
    end

    -- Configure a row as a child snippet (indented)
    local function SetupChildRow(row, snippet)
        row.isProjectRow = false
        row.toggle:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 24, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetText(snippet.name or "Untitled")
        row.text:SetTextColor(0.83, 0.83, 0.83, 1)
    end

    -- Configure a row as a standalone snippet (no indent)
    local function SetupStandaloneRow(row, snippet)
        row.isProjectRow = false
        row.toggle:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetText(snippet.name or "Untitled")
        row.text:SetTextColor(0.83, 0.83, 0.83, 1)
    end

    function list:Refresh()
        self:HideAllRows()

        local topLevel = DF.SnippetStore:GetTopLevel()
        local contentW = self.pane:GetContent():GetWidth()
        local yOffset = 0
        local rowIndex = 0

        for _, snippet in ipairs(topLevel) do
            rowIndex = rowIndex + 1
            local row = self:GetRow(rowIndex)
            row:SetWidth(contentW)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
            row.snippetId = snippet.id

            if snippet.isProject then
                -- Default new projects to expanded
                if self.expanded[snippet.id] == nil then
                    self.expanded[snippet.id] = true
                end
                local isExpanded = self.expanded[snippet.id]
                SetupProjectRow(row, snippet, isExpanded)

                -- Selection state (projects don't normally get selected, but handle it)
                if snippet.id == self.selectedId then
                    row.sel:Show()
                else
                    row.sel:Hide()
                end

                yOffset = yOffset + ROW_HEIGHT

                -- Render children if expanded
                if isExpanded then
                    local children = DF.SnippetStore:GetChildren(snippet.id)
                    for _, child in ipairs(children) do
                        rowIndex = rowIndex + 1
                        local childRow = self:GetRow(rowIndex)
                        childRow:SetWidth(contentW)
                        childRow:ClearAllPoints()
                        childRow:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
                        childRow.snippetId = child.id

                        SetupChildRow(childRow, child)

                        if child.id == self.selectedId then
                            childRow.sel:Show()
                        else
                            childRow.sel:Hide()
                        end

                        yOffset = yOffset + ROW_HEIGHT
                    end
                end
            else
                -- Standalone snippet
                SetupStandaloneRow(row, snippet)

                if snippet.id == self.selectedId then
                    row.sel:Show()
                else
                    row.sel:Hide()
                end

                yOffset = yOffset + ROW_HEIGHT
            end
        end

        self.pane:SetContentHeight(yOffset)
    end

    function list:UpdateSelection()
        for _, row in ipairs(self.rows) do
            if row:IsShown() then
                if row.snippetId == self.selectedId then
                    row.sel:Show()
                else
                    row.sel:Hide()
                end
            end
        end
    end

    function list:SetOnSelect(callback)
        self.onSelect = callback
    end

    function list:SetOnRightClick(callback)
        self.onRightClick = callback
    end

    function list:SetExpanded(id, state)
        self.expanded[id] = state
    end

    function list:SetSelected(id)
        self.selectedId = id
        self:UpdateSelection()
    end

    function list:GetSelected()
        return self.selectedId
    end

    -- Handle resize
    pane.frame:SetScript("OnSizeChanged", function()
        local w = pane.scrollFrame:GetWidth()
        if w > 0 then
            pane:GetContent():SetWidth(w)
            list:Refresh()
        end
    end)

    return list
end
