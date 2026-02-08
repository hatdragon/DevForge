local _, DF = ...

DF.ErrorList = {}

local ErrList = DF.ErrorList

local ROW_HEIGHT = DF.Layout.rowHeight

function ErrList:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)

    local list = {
        frame = pane.frame,
        pane = pane,
        rows = {},
        selectedId = nil,
        onSelect = nil,
        items = {},
    }

    function list:GetRow(index)
        if self.rows[index] then
            self.rows[index]:Show()
            return self.rows[index]
        end

        local row = CreateFrame("Button", nil, self.pane:GetContent())
        row:RegisterForClicks("LeftButtonUp")
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

        -- Count badge
        local countText = row:CreateFontString(nil, "OVERLAY")
        countText:SetFontObject(DF.Theme:UIFont())
        countText:SetPoint("LEFT", 4, 0)
        countText:SetJustifyH("RIGHT")
        countText:SetWidth(30)
        countText:SetTextColor(0.6, 0.6, 0.6, 1)
        row.countText = countText

        -- Error message text
        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", countText, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", -50, 0)
        text:SetWordWrap(false)
        row.text = text

        -- Time text
        local timeText = row:CreateFontString(nil, "OVERLAY")
        timeText:SetFontObject(DF.Theme:UIFont())
        timeText:SetJustifyH("RIGHT")
        timeText:SetPoint("RIGHT", -4, 0)
        timeText:SetWidth(44)
        timeText:SetTextColor(0.45, 0.45, 0.45, 1)
        row.timeText = timeText

        row:SetScript("OnEnter", function(self)
            if self.errorId ~= list.selectedId then
                self.hl:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if self.errorId and list.onSelect then
                list.selectedId = self.errorId
                list:UpdateSelection()
                list.onSelect(self.errorId)
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

    function list:Refresh()
        self:HideAllRows()

        local allErrors = DF.ErrorHandler:GetErrors()
        self.items = allErrors
        local contentW = self.pane:GetContent():GetWidth()
        local yOffset = 0

        -- Show newest first
        for i = #allErrors, 1, -1 do
            local err = allErrors[i]
            local rowIdx = #allErrors - i + 1
            local row = self:GetRow(rowIdx)
            row:SetWidth(contentW)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)

            -- Count badge
            if err.counter > 1 then
                row.countText:SetText("x" .. err.counter)
            else
                row.countText:SetText("")
            end

            -- Truncated message (first line only)
            local firstLine = (err.message or ""):match("^([^\n]+)") or err.message or ""
            if #firstLine > 80 then
                firstLine = firstLine:sub(1, 77) .. "..."
            end
            row.text:SetText(firstLine)

            -- Color by type
            if err.type == "warning" then
                row.text:SetTextColor(0.9, 0.8, 0.3, 1)
            else
                row.text:SetTextColor(0.9, 0.4, 0.4, 1)
            end

            -- Time (just HH:MM)
            local timeStr = (err.time or ""):match("(%d+:%d+):%d+$") or ""
            row.timeText:SetText(timeStr)

            row.errorId = err.id

            -- Selection state
            if err.id == self.selectedId then
                row.sel:Show()
            else
                row.sel:Hide()
            end

            yOffset = yOffset + ROW_HEIGHT
        end

        self.pane:SetContentHeight(yOffset)
    end

    function list:UpdateSelection()
        for _, row in ipairs(self.rows) do
            if row:IsShown() then
                if row.errorId == self.selectedId then
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
