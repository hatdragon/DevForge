local _, DF = ...

DF.PerfTable = {}

local PerfTable = DF.PerfTable

local ROW_HEIGHT = DF.Layout.rowHeight
local VISIBLE_ROWS = 40

function PerfTable:Create(parent)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(container)

    local tbl = {
        frame = container,
        rows = {},
        flatList = {},
        sortKey = "memory",
        sortAsc = false,
        scrollOffset = 0,
        searchFilter = "",
        headerHeight = ROW_HEIGHT + 2,
    }

    -- Column definitions
    local COLUMNS = {
        { key = "name",        label = "Addon",     relWidth = 0.38, align = "LEFT" },
        { key = "memory",      label = "Mem (KB)",   relWidth = 0.14, align = "RIGHT" },
        { key = "memoryDelta", label = "Delta",     relWidth = 0.12, align = "RIGHT" },
        { key = "memoryPeak",  label = "Peak",      relWidth = 0.12, align = "RIGHT" },
        { key = "cpu",         label = "CPU (ms)",   relWidth = 0.12, align = "RIGHT", cpuOnly = true },
        { key = "cpuPerSec",   label = "CPU/s",     relWidth = 0.12, align = "RIGHT", cpuOnly = true },
    }

    -- Header row
    local header = CreateFrame("Frame", nil, container)
    header:SetHeight(tbl.headerHeight)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", -DF.Layout.scrollbarWidth, 0)

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local headerBtns = {}
    for i, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetHeight(tbl.headerHeight)

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetText(col.label)
        text:SetTextColor(0.7, 0.75, 0.85, 1)
        text:SetJustifyH(col.align)
        if col.align == "LEFT" then
            text:SetPoint("LEFT", 6, 0)
            text:SetPoint("RIGHT", -2, 0)
        else
            text:SetPoint("LEFT", 2, 0)
            text:SetPoint("RIGHT", -6, 0)
        end
        btn.text = text

        -- Sort arrow
        local arrow = btn:CreateFontString(nil, "OVERLAY")
        arrow:SetFontObject(DF.Theme:UIFont())
        arrow:SetPoint("RIGHT", text, "LEFT", -2, 0)
        arrow:SetTextColor(0.5, 0.6, 0.8, 1)
        arrow:SetText("")
        btn.arrow = arrow

        btn:SetScript("OnClick", function()
            if tbl.sortKey == col.key then
                tbl.sortAsc = not tbl.sortAsc
            else
                tbl.sortKey = col.key
                tbl.sortAsc = false
            end
            tbl:SortAndUpdate()
        end)

        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(0.7, 0.75, 0.85, 1)
        end)

        headerBtns[i] = btn
        btn.colDef = col
    end
    tbl.headerBtns = headerBtns

    -- Scrollbar
    local scrollbar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    scrollbar:SetWidth(DF.Layout.scrollbarWidth)
    scrollbar:SetPoint("TOPRIGHT", 0, -tbl.headerHeight)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollbar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    scrollbar:SetBackdropColor(0.08, 0.08, 0.1, 1)

    local thumb = CreateFrame("Frame", nil, scrollbar, "BackdropTemplate")
    thumb:SetWidth(DF.Layout.scrollbarWidth - 2)
    thumb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    thumb:SetBackdropColor(0.35, 0.35, 0.4, 1)
    thumb:SetPoint("TOP", 1, 0)
    thumb:SetHeight(30)
    tbl.scrollbar = scrollbar
    tbl.thumb = thumb

    -- Row container
    local rowContainer = CreateFrame("Frame", nil, container)
    rowContainer:SetPoint("TOPLEFT", 0, -tbl.headerHeight)
    rowContainer:SetPoint("BOTTOMRIGHT", -DF.Layout.scrollbarWidth, 0)
    tbl.rowContainer = rowContainer

    local function GetRow(index)
        if tbl.rows[index] then
            tbl.rows[index]:Show()
            return tbl.rows[index]
        end

        local row = CreateFrame("Frame", nil, rowContainer)
        row:SetHeight(ROW_HEIGHT)

        -- Alternating bg
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        row.bg = bg

        -- Column texts
        row.cols = {}
        for ci, col in ipairs(COLUMNS) do
            local ft = row:CreateFontString(nil, "OVERLAY")
            ft:SetFontObject(DF.Theme:UIFont())
            ft:SetJustifyH(col.align)
            ft:SetWordWrap(false)
            ft:SetTextColor(0.83, 0.83, 0.83, 1)
            row.cols[ci] = ft
        end

        tbl.rows[index] = row
        return row
    end

    function tbl:LayoutColumns()
        local totalW = self.rowContainer:GetWidth()
        if totalW <= 0 then return end

        local profilingOn = DF.PerfData:IsProfilingEnabled()
        local visibleW = 0
        for _, col in ipairs(COLUMNS) do
            if not col.cpuOnly or profilingOn then
                visibleW = visibleW + col.relWidth
            end
        end

        local xOff = 0
        for i, col in ipairs(COLUMNS) do
            local btn = self.headerBtns[i]
            if col.cpuOnly and not profilingOn then
                btn:Hide()
            else
                local w = math.floor(totalW * col.relWidth / visibleW)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", header, "TOPLEFT", xOff, 0)
                btn:SetWidth(w)
                btn:Show()

                -- Update sort arrow
                if self.sortKey == col.key then
                    btn.arrow:SetText(self.sortAsc and "^" or "v")
                else
                    btn.arrow:SetText("")
                end

                xOff = xOff + w
            end
        end
    end

    function tbl:BuildList()
        local all = DF.PerfData:GetSnapshots()
        local filter = self.searchFilter:lower()
        wipe(self.flatList)
        for _, snap in ipairs(all) do
            if filter == "" or snap.name:lower():find(filter, 1, true) then
                self.flatList[#self.flatList + 1] = snap
            end
        end
    end

    function tbl:SortList()
        local key = self.sortKey
        local asc = self.sortAsc
        table.sort(self.flatList, function(a, b)
            local av = a[key]
            local bv = b[key]
            if av == nil then av = 0 end
            if bv == nil then bv = 0 end
            if key == "name" then
                if asc then return av:lower() < bv:lower()
                else return av:lower() > bv:lower() end
            else
                if asc then return av < bv
                else return av > bv end
            end
        end)
    end

    function tbl:UpdateRows()
        -- Hide all
        for _, row in ipairs(self.rows) do
            row:Hide()
        end

        local totalW = self.rowContainer:GetWidth()
        if totalW <= 0 then return end
        local containerH = self.rowContainer:GetHeight()
        local maxVisible = math.floor(containerH / ROW_HEIGHT)
        local profilingOn = DF.PerfData:IsProfilingEnabled()

        -- Calculate visible column widths
        local visibleW = 0
        for _, col in ipairs(COLUMNS) do
            if not col.cpuOnly or profilingOn then
                visibleW = visibleW + col.relWidth
            end
        end

        for vi = 1, maxVisible do
            local di = vi + self.scrollOffset
            local snap = self.flatList[di]
            if not snap then break end

            local row = GetRow(vi)
            row:SetWidth(totalW)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.rowContainer, "TOPLEFT", 0, -(vi - 1) * ROW_HEIGHT)

            -- Alternating bg
            if di % 2 == 0 then
                row.bg:SetColorTexture(0.12, 0.12, 0.14, 1)
            else
                row.bg:SetColorTexture(0.1, 0.1, 0.12, 1)
            end

            -- Color by memory usage
            local memColor = { 0.83, 0.83, 0.83 }
            if snap.memory > 10240 then
                memColor = { 0.9, 0.35, 0.35 }
            elseif snap.memory > 5120 then
                memColor = { 0.9, 0.6, 0.3 }
            elseif snap.memory > 1024 then
                memColor = { 0.9, 0.9, 0.4 }
            end

            -- Position column texts
            local xOff = 0
            for ci, col in ipairs(COLUMNS) do
                local ft = row.cols[ci]
                if col.cpuOnly and not profilingOn then
                    ft:Hide()
                else
                    ft:Show()
                    local w = math.floor(totalW * col.relWidth / visibleW)
                    ft:ClearAllPoints()
                    if col.align == "LEFT" then
                        ft:SetPoint("LEFT", row, "LEFT", xOff + 6, 0)
                        ft:SetWidth(w - 8)
                    else
                        ft:SetPoint("RIGHT", row, "LEFT", xOff + w - 6, 0)
                        ft:SetWidth(w - 8)
                    end

                    -- Format value
                    local val = snap[col.key]
                    local text = ""
                    if col.key == "name" then
                        text = val or ""
                        ft:SetTextColor(0.83, 0.83, 0.83, 1)
                    elseif col.key == "memory" or col.key == "memoryPeak" then
                        text = format("%.0f", val or 0)
                        ft:SetTextColor(unpack(memColor))
                    elseif col.key == "memoryDelta" then
                        local d = val or 0
                        if d > 0 then
                            text = "+" .. format("%.0f", d)
                            ft:SetTextColor(0.9, 0.6, 0.3, 1)
                        elseif d < 0 then
                            text = format("%.0f", d)
                            ft:SetTextColor(0.5, 0.8, 0.5, 1)
                        else
                            text = "0"
                            ft:SetTextColor(0.5, 0.5, 0.5, 1)
                        end
                    elseif col.key == "cpu" then
                        text = val and format("%.1f", val) or "-"
                        ft:SetTextColor(0.75, 0.75, 0.85, 1)
                    elseif col.key == "cpuPerSec" then
                        text = val and format("%.2f", val) or "-"
                        ft:SetTextColor(0.75, 0.75, 0.85, 1)
                    end
                    ft:SetText(text)

                    xOff = xOff + w
                end
            end
        end

        -- Update scrollbar
        self:UpdateThumb()
    end

    function tbl:UpdateThumb()
        local total = #self.flatList
        local containerH = self.rowContainer:GetHeight()
        local maxVisible = math.floor(containerH / ROW_HEIGHT)
        if total <= maxVisible or total == 0 then
            self.thumb:Hide()
            return
        end
        self.thumb:Show()

        local barH = self.scrollbar:GetHeight()
        local thumbH = math.max(20, barH * (maxVisible / total))
        self.thumb:SetHeight(thumbH)

        local scrollRange = total - maxVisible
        local ratio = (scrollRange > 0) and (self.scrollOffset / scrollRange) or 0
        local yOff = ratio * (barH - thumbH)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.scrollbar, "TOP", 1, -yOff)
    end

    function tbl:SetSearchFilter(text)
        self.searchFilter = text or ""
        self.scrollOffset = 0
        self:SortAndUpdate()
    end

    function tbl:SortAndUpdate()
        self:BuildList()
        self:SortList()
        self:LayoutColumns()
        self:UpdateRows()
    end

    -- Mouse wheel scrolling
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #tbl.flatList - math.floor(tbl.rowContainer:GetHeight() / ROW_HEIGHT))
        tbl.scrollOffset = math.max(0, math.min(maxOffset, tbl.scrollOffset - delta * 3))
        tbl:UpdateRows()
    end)

    -- Handle resize
    container:SetScript("OnSizeChanged", function()
        tbl:LayoutColumns()
        tbl:UpdateRows()
    end)

    return tbl
end
