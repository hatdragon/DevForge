local _, DF = ...

DF.Widgets = DF.Widgets or {}

--[[
    PropertyGrid: Two-column key/value display with section headers.

    Usage:
        local grid = DF.Widgets:CreatePropertyGrid(parent)
        grid:SetSections({
            { title = "Identity", props = { { key = "Name", value = "MyFrame" }, ... } },
            { title = "Geometry", props = { ... } },
        })
]]

local ROW_HEIGHT = DF.Layout.rowHeight
local LABEL_W = DF.Layout.propertyLabelW

function DF.Widgets:CreatePropertyGrid(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)

    local grid = {
        frame = pane.frame,
        pane = pane,
        rows = {},       -- pooled row frames
        sections = {},
    }

    -- Get or create a row
    function grid:GetRow(index)
        if self.rows[index] then
            self.rows[index]:Show()
            return self.rows[index]
        end

        local row = CreateFrame("Button", nil, self.pane:GetContent())
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        -- Alternating background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.14, 0.14, 0.16, 0.5)
        bg:Hide()
        row.bg = bg

        -- Section header background
        local headerBg = row:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints()
        headerBg:SetColorTexture(0.18, 0.18, 0.22, 1)
        headerBg:Hide()
        row.headerBg = headerBg

        -- Clickable row hover highlight
        local clickHl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        clickHl:SetAllPoints()
        clickHl:SetColorTexture(0.3, 0.5, 0.8, 0.15)
        clickHl:Hide()
        row.clickHl = clickHl

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", 6, 0)
        label:SetWidth(LABEL_W - 10)
        label:SetWordWrap(false)
        row.label = label

        -- Value
        local value = row:CreateFontString(nil, "OVERLAY")
        value:SetFontObject(DF.Theme:CodeFont())
        value:SetJustifyH("LEFT")
        value:SetPoint("LEFT", LABEL_W + 4, 0)
        value:SetPoint("RIGHT", -6, 0)
        value:SetWordWrap(false)
        row.value = value

        -- Click / hover wiring (configured per-refresh in SetClickable)
        row:SetScript("OnClick", function(self)
            if self._onClick then self._onClick() end
        end)
        row:SetScript("OnEnter", function(self)
            if self._onClick then self.clickHl:Show() end
        end)
        row:SetScript("OnLeave", function(self)
            self.clickHl:Hide()
        end)

        self.rows[index] = row
        return row
    end

    -- Configure a row as clickable (or not)
    local function SetClickable(row, onClick)
        row._onClick = onClick
        if onClick then
            row:EnableMouse(true)
            row.value:SetTextColor(0.4, 0.7, 1, 1)
        else
            row:EnableMouse(false)
            row.clickHl:Hide()
            row.value:SetTextColor(0.83, 0.83, 0.83, 1)
        end
    end

    function grid:HideAllRows()
        for _, row in ipairs(self.rows) do
            row:Hide()
        end
    end

    function grid:SetSections(sections)
        self.sections = sections or {}
        self:Refresh()
        self.pane:ScrollToTop()
    end

    function grid:Refresh()
        self:HideAllRows()

        local contentW = self.pane:GetContent():GetWidth()
        if contentW <= 0 then contentW = 400 end
        local rowIdx = 0
        local yOffset = 0

        for _, section in ipairs(self.sections) do
            -- Section header
            rowIdx = rowIdx + 1
            local headerRow = self:GetRow(rowIdx)
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
            headerRow:SetWidth(contentW)
            headerRow.headerBg:Show()
            headerRow.bg:Hide()
            SetClickable(headerRow, nil)
            headerRow.label:SetText(section.title or "")
            headerRow.label:SetTextColor(0.6, 0.75, 1, 1)
            headerRow.label:SetWidth(contentW - 12)
            headerRow.value:SetText("")
            yOffset = yOffset + ROW_HEIGHT

            -- Properties
            if section.props then
                for i, prop in ipairs(section.props) do
                    rowIdx = rowIdx + 1
                    local row = self:GetRow(rowIdx)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", self.pane:GetContent(), "TOPLEFT", 0, -yOffset)
                    row:SetWidth(contentW)
                    row.headerBg:Hide()

                    if i % 2 == 0 then
                        row.bg:Show()
                    else
                        row.bg:Hide()
                    end

                    row.label:SetText(prop.key or "")
                    row.label:SetTextColor(0.65, 0.65, 0.65, 1)
                    row.label:SetWidth(LABEL_W - 10)
                    row.value:SetText(prop.value or "")
                    SetClickable(row, prop.onClick)
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end

        self.pane:SetContentHeight(yOffset)
    end

    function grid:Clear()
        self:SetSections({})
    end

    return grid
end
