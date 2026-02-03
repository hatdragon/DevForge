local _, DF = ...

DF.MacroList = {}

local MacList = DF.MacroList

local ROW_HEIGHT = DF.Layout.rowHeight
local HEADER_HEIGHT = 20

function MacList:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)

    local list = {
        frame = pane.frame,
        pane = pane,
        rows = {},
        selectedIndex = nil,
        onSelect = nil,
    }

    function list:GetRow(idx)
        if self.rows[idx] then
            self.rows[idx]:Show()
            return self.rows[idx]
        end

        local row = CreateFrame("Button", nil, self.pane:GetContent())
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

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 6, 0)
        row.icon = icon

        -- Name text
        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", -8, 0)
        text:SetWordWrap(false)
        text:SetTextColor(0.83, 0.83, 0.83, 1)
        row.text = text

        -- Header background (reused for section headers)
        local headerBg = row:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints()
        headerBg:SetColorTexture(0.15, 0.15, 0.18, 1)
        headerBg:Hide()
        row.headerBg = headerBg

        row:SetScript("OnEnter", function(self)
            if not self.isHeader and self.macroIndex ~= list.selectedIndex then
                self.hl:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if not self.isHeader and self.macroIndex and list.onSelect then
                list.selectedIndex = self.macroIndex
                list:UpdateSelection()
                list.onSelect(self.macroIndex)
            end
        end)

        self.rows[idx] = row
        return row
    end

    function list:HideAllRows()
        for _, row in ipairs(self.rows) do
            row:Hide()
        end
    end

    function list:Refresh()
        self:HideAllRows()

        local allMacros = DF.MacroStore:GetAll()
        local numAccount, numCharacter = DF.MacroStore:GetCounts()
        local maxAccount, maxCharacter = DF.MacroStore:GetMaxCounts()
        local contentW = self.pane:GetContent():GetWidth()
        local yOffset = 0
        local rowIdx = 0

        -- Account Macros header
        rowIdx = rowIdx + 1
        local hdr1 = self:GetRow(rowIdx)
        hdr1:SetWidth(contentW)
        hdr1:ClearAllPoints()
        hdr1:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
        hdr1:SetHeight(HEADER_HEIGHT)
        hdr1.icon:Hide()
        hdr1.sel:Hide()
        hdr1.headerBg:Show()
        hdr1.text:SetPoint("LEFT", 6, 0)
        hdr1.text:SetText(format("Account Macros (%d/%d)", numAccount, maxAccount))
        hdr1.text:SetTextColor(0.6, 0.7, 0.85, 1)
        hdr1.isHeader = true
        hdr1.macroIndex = nil
        yOffset = yOffset + HEADER_HEIGHT

        -- Account macro rows
        for _, macro in ipairs(allMacros) do
            if not macro.isCharacter then
                rowIdx = rowIdx + 1
                local row = self:GetRow(rowIdx)
                row:SetWidth(contentW)
                row:SetHeight(ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
                row.headerBg:Hide()
                row.icon:Show()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 6, 0)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", -8, 0)

                if macro.icon then
                    row.icon:SetTexture(macro.icon)
                else
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                row.text:SetText(macro.name or "")
                row.text:SetTextColor(0.83, 0.83, 0.83, 1)
                row.macroIndex = macro.index
                row.isHeader = false

                if macro.index == self.selectedIndex then
                    row.sel:Show()
                else
                    row.sel:Hide()
                end

                yOffset = yOffset + ROW_HEIGHT
            end
        end

        -- Character Macros header
        rowIdx = rowIdx + 1
        local hdr2 = self:GetRow(rowIdx)
        hdr2:SetWidth(contentW)
        hdr2:ClearAllPoints()
        hdr2:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
        hdr2:SetHeight(HEADER_HEIGHT)
        hdr2.icon:Hide()
        hdr2.sel:Hide()
        hdr2.headerBg:Show()
        hdr2.text:ClearAllPoints()
        hdr2.text:SetPoint("LEFT", 6, 0)
        hdr2.text:SetText(format("Character Macros (%d/%d)", numCharacter, maxCharacter))
        hdr2.text:SetTextColor(0.6, 0.7, 0.85, 1)
        hdr2.isHeader = true
        hdr2.macroIndex = nil
        yOffset = yOffset + HEADER_HEIGHT

        -- Character macro rows
        for _, macro in ipairs(allMacros) do
            if macro.isCharacter then
                rowIdx = rowIdx + 1
                local row = self:GetRow(rowIdx)
                row:SetWidth(contentW)
                row:SetHeight(ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
                row.headerBg:Hide()
                row.icon:Show()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 6, 0)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", -8, 0)

                if macro.icon then
                    row.icon:SetTexture(macro.icon)
                else
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                row.text:SetText(macro.name or "")
                row.text:SetTextColor(0.83, 0.83, 0.83, 1)
                row.macroIndex = macro.index
                row.isHeader = false

                if macro.index == self.selectedIndex then
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
            if row:IsShown() and not row.isHeader then
                if row.macroIndex == self.selectedIndex then
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

    function list:SetSelected(index)
        self.selectedIndex = index
        self:UpdateSelection()
    end

    function list:GetSelected()
        return self.selectedIndex
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
