local _, DF = ...

DF.EventMonitorFilter = {}

local Filter = DF.EventMonitorFilter

local ROW_HEIGHT = DF.Layout.rowHeight
local INDENT = DF.Layout.treeIndent

-- Row types
local ROW_CATEGORY = 1
local ROW_EVENT    = 2

function Filter:Create(parent)
    local panel = {
        expanded = {},       -- categoryName -> true
        flatList = {},       -- built from categories + expand state
        rowPool = {},
        visibleRows = {},
        scrollOffset = 0,
        searchQuery = "",
        onChanged = nil,
    }

    ---------------------------------------------------------------------------
    -- Main frame
    ---------------------------------------------------------------------------
    local frame = CreateFrame("Frame", nil, parent)
    panel.frame = frame

    ---------------------------------------------------------------------------
    -- Toolbar: [All On] [All Off]  [Search...]
    ---------------------------------------------------------------------------
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetHeight(26)
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", 0, 0)

    local allOnBtn = DF.Widgets:CreateButton(toolbar, "All On", 50, 20)
    allOnBtn:SetPoint("LEFT", 2, 0)

    local allOffBtn = DF.Widgets:CreateButton(toolbar, "All Off", 50, 20)
    allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 4, 0)

    local searchBox = DF.Widgets:CreateSearchBox(toolbar, "Search events...", 22)
    searchBox.frame:SetPoint("LEFT", allOffBtn, "RIGHT", 6, 0)
    searchBox.frame:SetPoint("RIGHT", -2, 0)

    ---------------------------------------------------------------------------
    -- Info banner
    ---------------------------------------------------------------------------
    local banner = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    banner:SetHeight(20)
    banner:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    banner:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)
    local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints()
    bannerBg:SetColorTexture(0.35, 0.25, 0.05, 0.6)
    local bannerText = banner:CreateFontString(nil, "OVERLAY")
    bannerText:SetFontObject(DF.Theme:UIFont())
    bannerText:SetPoint("LEFT", 6, 0)
    bannerText:SetPoint("RIGHT", -6, 0)
    bannerText:SetJustifyH("LEFT")
    bannerText:SetTextColor(0.9, 0.75, 0.3, 1)
    bannerText:SetText("This list may be incomplete. New events are discovered automatically while capturing.")

    ---------------------------------------------------------------------------
    -- Scroll area
    ---------------------------------------------------------------------------
    local container = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(container, true)
    container:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -2)
    container:SetPoint("BOTTOMRIGHT", 0, 0)

    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 3, -3)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(DF.Layout.scrollbarWidth + 3), 3)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    -- Scrollbar
    local scrollbar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    scrollbar:SetWidth(DF.Layout.scrollbarWidth)
    scrollbar:SetPoint("TOPRIGHT", -3, -3)
    scrollbar:SetPoint("BOTTOMRIGHT", -3, 3)
    scrollbar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    scrollbar:SetBackdropColor(0.08, 0.08, 0.10, 0.5)

    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(DF.Layout.scrollbarWidth - 2)
    thumb:SetHeight(40)
    thumb:SetPoint("TOP", 0, 0)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(unpack(DF.Colors.scrollbar))

    panel.scrollFrame = scrollFrame
    panel.content = content
    panel.scrollbar = scrollbar
    panel.thumb = thumb

    ---------------------------------------------------------------------------
    -- Helpers: blacklist state queries
    ---------------------------------------------------------------------------
    local function IsEventEnabled(event)
        return not DF.EventMonitorLog:IsBlacklisted(event)
    end

    -- Returns "all", "none", or "mixed"
    local function CategoryState(cat)
        local allOn, allOff = true, true
        for _, entry in ipairs(cat.events) do
            if DF.EventMonitorLog:IsBlacklisted(entry.event) then
                allOn = false
            else
                allOff = false
            end
        end
        if allOn then return "all" end
        if allOff then return "none" end
        return "mixed"
    end

    local function NotifyChanged()
        if panel.onChanged then
            panel.onChanged()
        end
    end

    ---------------------------------------------------------------------------
    -- Flatten categories + events into rows
    ---------------------------------------------------------------------------
    function panel:BuildFlatList()
        self.flatList = {}
        local q = self.searchQuery:lower()
        local categories = DF.EventIndex:GetCategories()

        for _, cat in ipairs(categories) do
            -- Collect matching events
            local matchingEvents = {}
            for _, entry in ipairs(cat.events) do
                if q == "" or entry.event:lower():find(q, 1, true) or entry.desc:lower():find(q, 1, true) then
                    matchingEvents[#matchingEvents + 1] = entry
                end
            end

            if #matchingEvents > 0 then
                self.flatList[#self.flatList + 1] = {
                    type = ROW_CATEGORY,
                    cat = cat,
                    matchCount = #matchingEvents,
                }

                if self.expanded[cat.name] then
                    for _, entry in ipairs(matchingEvents) do
                        self.flatList[#self.flatList + 1] = {
                            type = ROW_EVENT,
                            event = entry.event,
                            desc = entry.desc,
                            cat = cat,
                        }
                    end
                end
            end
        end

        -- Discovered events (runtime-captured, persisted across sessions)
        local discoveredEvents = DF.EventIndex:GetDiscovered()
        if #discoveredEvents > 0 then
            local discoveredCat = { name = "Discovered", events = discoveredEvents }

            -- Apply search filter
            local matchingDiscovered = {}
            for _, entry in ipairs(discoveredEvents) do
                if q == "" or entry.event:lower():find(q, 1, true) then
                    matchingDiscovered[#matchingDiscovered + 1] = entry
                end
            end

            if #matchingDiscovered > 0 then
                self.flatList[#self.flatList + 1] = {
                    type = ROW_CATEGORY,
                    cat = discoveredCat,
                    matchCount = #matchingDiscovered,
                }

                if self.expanded[discoveredCat.name] then
                    for _, entry in ipairs(matchingDiscovered) do
                        self.flatList[#self.flatList + 1] = {
                            type = ROW_EVENT,
                            event = entry.event,
                            desc = entry.desc,
                            cat = discoveredCat,
                        }
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Checkbox drawing helper
    ---------------------------------------------------------------------------
    local function DrawCheckbox(tex, checkmark, state)
        -- state: true = checked, false = unchecked, "mixed" = partial
        if state == true or state == "all" then
            tex:SetColorTexture(0.34, 0.61, 0.84, 1)  -- blue
            checkmark:SetText("\226\156\147")  -- checkmark
            checkmark:Show()
        elseif state == "mixed" then
            tex:SetColorTexture(0.45, 0.45, 0.50, 1)  -- gray-blue
            checkmark:SetText("-")
            checkmark:Show()
        else
            tex:SetColorTexture(0.25, 0.25, 0.28, 1)  -- dark
            checkmark:Hide()
        end
    end

    ---------------------------------------------------------------------------
    -- Row pool
    ---------------------------------------------------------------------------
    function panel:GetRow(index)
        if self.rowPool[index] then
            return self.rowPool[index]
        end

        local row = CreateFrame("Button", nil, self.content)
        row:SetHeight(ROW_HEIGHT)

        -- Hover highlight
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(unpack(DF.Colors.highlight))
        hl:Hide()
        row.hl = hl

        -- Checkbox background
        local cbBg = row:CreateTexture(nil, "ARTWORK")
        cbBg:SetSize(12, 12)
        row.cbBg = cbBg

        -- Checkbox checkmark
        local cbMark = row:CreateFontString(nil, "OVERLAY")
        cbMark:SetFontObject(DF.Theme:UIFont())
        cbMark:SetPoint("CENTER", cbBg, "CENTER", 0, 0)
        cbMark:SetTextColor(1, 1, 1, 1)
        row.cbMark = cbMark

        -- Expand/collapse toggle (categories only)
        local toggle = row:CreateFontString(nil, "OVERLAY")
        toggle:SetFontObject(DF.Theme:UIFont())
        toggle:SetTextColor(0.6, 0.6, 0.6, 1)
        row.toggle = toggle

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.83, 0.83, 0.83, 1)
        row.label = label

        row:SetScript("OnEnter", function(self) self.hl:Show() end)
        row:SetScript("OnLeave", function(self) self.hl:Hide() end)

        row:SetScript("OnClick", function(self)
            local data = self.data
            if not data then return end

            if data.type == ROW_CATEGORY then
                -- Shift-click: toggle expand/collapse
                -- Normal click: also toggle expand/collapse
                local catName = data.cat.name
                panel.expanded[catName] = not panel.expanded[catName]
                panel:Refresh()
            elseif data.type == ROW_EVENT then
                -- Toggle blacklist
                local current = DF.EventMonitorLog:IsBlacklisted(data.event)
                DF.EventMonitorLog:SetBlacklisted(data.event, not current)
                panel:Refresh()
                NotifyChanged()
            end
        end)

        -- Right-click on category checkbox area: toggle all events
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:HookScript("OnClick", function(self, button)
            local data = self.data
            if not data or data.type ~= ROW_CATEGORY then return end
            -- We handle category checkbox toggle separately via the checkbox region
        end)

        self.rowPool[index] = row
        return row
    end

    ---------------------------------------------------------------------------
    -- Checkbox click region (overlaid on cbBg area)
    ---------------------------------------------------------------------------
    local function SetupCheckboxClick(row)
        if row.cbBtn then return end
        local cbBtn = CreateFrame("Button", nil, row)
        cbBtn:RegisterForClicks("LeftButtonUp")
        cbBtn:SetSize(16, 16)
        cbBtn:SetPoint("CENTER", row.cbBg, "CENTER", 0, 0)
        cbBtn:SetScript("OnClick", function()
            local data = row.data
            if not data then return end

            if data.type == ROW_EVENT then
                local current = DF.EventMonitorLog:IsBlacklisted(data.event)
                DF.EventMonitorLog:SetBlacklisted(data.event, not current)
                panel:Refresh()
                NotifyChanged()
            elseif data.type == ROW_CATEGORY then
                local state = CategoryState(data.cat)
                -- If all enabled or mixed, disable all. If all disabled, enable all.
                local newBlacklisted = (state ~= "none")
                for _, entry in ipairs(data.cat.events) do
                    DF.EventMonitorLog:SetBlacklisted(entry.event, newBlacklisted)
                end
                panel:Refresh()
                NotifyChanged()
            end
        end)
        cbBtn:SetScript("OnEnter", function() row.hl:Show() end)
        cbBtn:SetScript("OnLeave", function() row.hl:Hide() end)
        row.cbBtn = cbBtn
    end

    ---------------------------------------------------------------------------
    -- Render visible rows
    ---------------------------------------------------------------------------
    function panel:UpdateRows()
        local viewH = self.scrollFrame:GetHeight()
        if viewH <= 0 then return end
        local visibleCount = math.ceil(viewH / ROW_HEIGHT) + 1
        local startIdx = math.floor(self.scrollOffset / ROW_HEIGHT) + 1
        local contentW = self.scrollFrame:GetWidth()

        for _, row in pairs(self.visibleRows) do
            row:Hide()
        end
        self.visibleRows = {}

        for i = 0, visibleCount - 1 do
            local dataIdx = startIdx + i
            local data = self.flatList[dataIdx]
            if not data then break end

            local row = self:GetRow(i + 1)
            row:SetWidth(contentW)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0,
                -((dataIdx - 1) * ROW_HEIGHT - self.scrollOffset))

            row.data = data
            SetupCheckboxClick(row)

            -- Clear sub-element anchors to avoid stacking when rows are recycled
            row.cbBg:ClearAllPoints()
            row.toggle:ClearAllPoints()
            row.label:ClearAllPoints()

            if data.type == ROW_CATEGORY then
                local indent = 2
                row.cbBg:SetPoint("LEFT", indent, 0)
                row.cbBg:Show()

                local state = CategoryState(data.cat)
                DrawCheckbox(row.cbBg, row.cbMark, state)

                row.toggle:Show()
                row.toggle:SetPoint("LEFT", indent + 16, 0)
                row.toggle:SetText(self.expanded[data.cat.name] and "-" or "+")

                row.label:SetPoint("LEFT", indent + 28, 0)
                row.label:SetPoint("RIGHT", -4, 0)
                row.label:SetText(data.cat.name .. " (" .. data.matchCount .. ")")
                row.label:SetTextColor(0.83, 0.83, 0.83, 1)
            elseif data.type == ROW_EVENT then
                local indent = INDENT + 6
                row.cbBg:SetPoint("LEFT", indent, 0)
                row.cbBg:Show()

                local enabled = IsEventEnabled(data.event)
                DrawCheckbox(row.cbBg, row.cbMark, enabled)

                row.toggle:Hide()

                row.label:SetPoint("LEFT", indent + 16, 0)
                row.label:SetPoint("RIGHT", -4, 0)
                row.label:SetText(data.event)
                if enabled then
                    row.label:SetTextColor(0.83, 0.83, 0.83, 1)
                else
                    row.label:SetTextColor(0.5, 0.5, 0.5, 1)
                end
            end

            row:Show()
            self.visibleRows[i + 1] = row
        end
    end

    ---------------------------------------------------------------------------
    -- Scrollbar thumb
    ---------------------------------------------------------------------------
    function panel:UpdateThumb()
        local totalH = #self.flatList * ROW_HEIGHT
        local viewH = self.scrollFrame:GetHeight()
        if totalH <= viewH or totalH <= 0 or viewH <= 0 then
            self.thumb:Hide()
            return
        end
        self.thumb:Show()

        local ratio = viewH / totalH
        local trackH = self.scrollbar:GetHeight()
        if trackH <= 0 then
            self.thumb:Hide()
            return
        end
        local thumbH = math.max(20, trackH * ratio)
        self.thumb:SetHeight(thumbH)

        local maxScroll = totalH - viewH
        local scrollRatio = (maxScroll > 0) and (self.scrollOffset / maxScroll) or 0
        local maxThumbOffset = trackH - thumbH
        local offset = scrollRatio * maxThumbOffset

        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.scrollbar, "TOP", 0, -offset)
    end

    ---------------------------------------------------------------------------
    -- Refresh
    ---------------------------------------------------------------------------
    function panel:Refresh()
        self:BuildFlatList()
        local totalH = #self.flatList * ROW_HEIGHT
        self.content:SetHeight(totalH)
        self.content:SetWidth(self.scrollFrame:GetWidth())

        -- Clamp scroll offset
        local viewH = self.scrollFrame:GetHeight()
        local maxScroll = math.max(0, totalH - viewH)
        if self.scrollOffset > maxScroll then
            self.scrollOffset = maxScroll
        end

        self:UpdateRows()
        self:UpdateThumb()
    end

    ---------------------------------------------------------------------------
    -- Public API
    ---------------------------------------------------------------------------
    function panel:SetOnChanged(callback)
        self.onChanged = callback
    end

    ---------------------------------------------------------------------------
    -- Button handlers
    ---------------------------------------------------------------------------
    allOnBtn:SetScript("OnClick", function()
        for _, data in ipairs(panel.flatList) do
            if data.type == ROW_CATEGORY then
                for _, entry in ipairs(data.cat.events) do
                    DF.EventMonitorLog:SetBlacklisted(entry.event, false)
                end
            end
        end
        panel:Refresh()
        NotifyChanged()
    end)

    allOffBtn:SetScript("OnClick", function()
        for _, data in ipairs(panel.flatList) do
            if data.type == ROW_CATEGORY then
                for _, entry in ipairs(data.cat.events) do
                    DF.EventMonitorLog:SetBlacklisted(entry.event, true)
                end
            end
        end
        panel:Refresh()
        NotifyChanged()
    end)

    searchBox:SetOnSearch(function(query)
        panel.searchQuery = (query or "")
        -- Auto-expand all when searching
        if panel.searchQuery ~= "" then
            local categories = DF.EventIndex:GetCategories()
            for _, cat in ipairs(categories) do
                panel.expanded[cat.name] = true
            end
            panel.expanded["Discovered"] = true
        end
        panel:Refresh()
    end)

    ---------------------------------------------------------------------------
    -- Scrollbar drag
    ---------------------------------------------------------------------------
    local isDragging = false
    local dragStartY, dragStartOffset

    thumb:EnableMouse(true)
    thumb:SetMovable(true)
    thumb:RegisterForDrag("LeftButton")

    thumb:SetScript("OnDragStart", function(self)
        isDragging = true
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartOffset = panel.scrollOffset
    end)

    thumb:SetScript("OnDragStop", function()
        isDragging = false
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not isDragging then return end
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local currentY = cursorY / scale
        local delta = dragStartY - currentY

        local totalH = #panel.flatList * ROW_HEIGHT
        local viewH = panel.scrollFrame:GetHeight()
        local maxScroll = math.max(0, totalH - viewH)
        local trackH = panel.scrollbar:GetHeight() - panel.thumb:GetHeight()
        if trackH <= 0 then return end

        local scrollRatio = delta / trackH
        panel.scrollOffset = DF.Util:Clamp(dragStartOffset + scrollRatio * maxScroll, 0, maxScroll)
        panel:UpdateRows()
        panel:UpdateThumb()
    end)

    -- Mouse wheel
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        local totalH = #panel.flatList * ROW_HEIGHT
        local viewH = panel.scrollFrame:GetHeight()
        local maxScroll = math.max(0, totalH - viewH)
        panel.scrollOffset = DF.Util:Clamp(panel.scrollOffset - delta * ROW_HEIGHT * 3, 0, maxScroll)
        panel:UpdateRows()
        panel:UpdateThumb()
    end)

    -- Resize handler
    container:SetScript("OnSizeChanged", function()
        C_Timer.After(0, function()
            local w = panel.scrollFrame:GetWidth()
            if w > 0 then
                panel.content:SetWidth(w)
            end
            panel:UpdateRows()
            panel:UpdateThumb()
        end)
    end)

    return panel
end
