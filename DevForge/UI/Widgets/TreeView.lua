local _, DF = ...

DF.Widgets = DF.Widgets or {}

--[[
    TreeView: Virtual-scrolling expandable tree widget.

    Node format:
    {
        id       = string,
        text     = string,
        icon     = string or nil,
        children = { node, ... } or nil,
        data     = any,           -- arbitrary user data
    }

    Usage:
        local tree = DF.Widgets:CreateTreeView(parent)
        tree:SetNodes(nodes)
        tree:SetOnSelect(function(node) ... end)
]]

local ROW_HEIGHT = DF.Layout.rowHeight
local INDENT = DF.Layout.treeIndent

function DF.Widgets:CreateTreeView(parent)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    DF.Theme:ApplyDarkPanel(container, true)

    -- Scroll frame
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

    -- State
    local tree = {
        frame = container,
        scrollFrame = scrollFrame,
        content = content,
        scrollbar = scrollbar,
        thumb = thumb,
        nodes = {},
        flatList = {},       -- flattened visible nodes
        expanded = {},       -- id -> true
        selectedId = nil,
        onSelect = nil,
        onRightClick = nil,
        rowPool = {},
        visibleRows = {},
        scrollOffset = 0,
    }

    -- Flatten the node tree respecting expanded state
    function tree:Flatten()
        self.flatList = {}
        local function walk(nodes, depth)
            for _, node in ipairs(nodes) do
                self.flatList[#self.flatList + 1] = { node = node, depth = depth }
                if node.children and #node.children > 0 and self.expanded[node.id] then
                    walk(node.children, depth + 1)
                end
            end
        end
        walk(self.nodes, 0)
    end

    -- Get or create a row frame
    function tree:GetRow(index)
        if self.rowPool[index] then
            return self.rowPool[index]
        end

        local row = CreateFrame("Button", nil, self.content)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHeight(ROW_HEIGHT)

        -- Highlight texture
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(unpack(DF.Colors.highlight))
        hl:Hide()
        row.hl = hl

        -- Selected texture
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(unpack(DF.Colors.rowSelected))
        sel:Hide()
        row.sel = sel

        -- Expand toggle
        local toggle = row:CreateFontString(nil, "OVERLAY")
        toggle:SetFontObject(DF.Theme:UIFont())
        toggle:SetText("+")
        toggle:SetTextColor(0.6, 0.6, 0.6, 1)
        row.toggle = toggle

        -- Icon (optional)
        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:Hide()
        row.icon = icon

        -- Text
        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(DF.Theme:UIFont())
        text:SetJustifyH("LEFT")
        text:SetTextColor(0.83, 0.83, 0.83, 1)
        row.text = text

        row:SetScript("OnEnter", function(self)
            if self.nodeId ~= tree.selectedId then
                self.hl:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            local entry = self.entry
            if not entry then return end

            -- Capture node data before any Refresh changes row assignments
            local node = entry.node
            local nodeId = node.id

            -- Right-click: delegate to callback
            if button == "RightButton" then
                if tree.onRightClick then
                    tree.onRightClick(node)
                end
                return
            end

            -- Toggle expand if has children
            if node.children and #node.children > 0 then
                tree.expanded[nodeId] = not tree.expanded[nodeId]
                tree:Refresh()
            end

            -- Select (always fires, even if already selected, for re-inspect)
            tree.selectedId = nodeId
            tree:UpdateSelection()
            if tree.onSelect then
                tree.onSelect(node)
            end
        end)

        self.rowPool[index] = row
        return row
    end

    -- Update visible rows based on scroll position
    function tree:UpdateRows()
        local viewH = self.scrollFrame:GetHeight()
        local visibleCount = math.ceil(viewH / ROW_HEIGHT) + 1
        local startIdx = math.floor(self.scrollOffset / ROW_HEIGHT) + 1
        local contentW = self.scrollFrame:GetWidth()

        -- Hide excess rows
        for i, row in pairs(self.visibleRows) do
            row:Hide()
        end
        self.visibleRows = {}

        for i = 0, visibleCount - 1 do
            local dataIdx = startIdx + i
            local entry = self.flatList[dataIdx]
            if not entry then break end

            local row = self:GetRow(i + 1)
            row:SetWidth(contentW)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -((dataIdx - 1) * ROW_HEIGHT - self.scrollOffset))

            local indent = entry.depth * INDENT
            local node = entry.node
            local hasChildren = node.children and #node.children > 0

            -- Toggle
            if hasChildren then
                row.toggle:Show()
                row.toggle:SetPoint("LEFT", indent + 2, 0)
                row.toggle:SetText(self.expanded[node.id] and "-" or "+")
            else
                row.toggle:Hide()
            end

            -- Icon
            local textOffset = indent + (hasChildren and 14 or 4)
            if node.icon then
                row.icon:Show()
                row.icon:SetTexture(node.icon)
                row.icon:SetPoint("LEFT", textOffset, 0)
                textOffset = textOffset + 18
            else
                row.icon:Hide()
            end

            -- Text
            row.text:SetPoint("LEFT", textOffset, 0)
            row.text:SetPoint("RIGHT", -4, 0)
            row.text:SetText(node.text or "")

            -- Selection
            row.nodeId = node.id
            row.entry = entry
            if node.id == self.selectedId then
                row.sel:Show()
            else
                row.sel:Hide()
            end

            row:Show()
            self.visibleRows[i + 1] = row
        end
    end

    function tree:UpdateSelection()
        for _, row in pairs(self.visibleRows) do
            if row.nodeId == self.selectedId then
                row.sel:Show()
            else
                row.sel:Hide()
            end
        end
    end

    function tree:UpdateThumb()
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

    function tree:Refresh()
        self:Flatten()
        local totalH = #self.flatList * ROW_HEIGHT
        self.content:SetHeight(totalH)
        self.content:SetWidth(self.scrollFrame:GetWidth())
        self:UpdateRows()
        self:UpdateThumb()
    end

    function tree:SetNodes(nodes)
        self.nodes = nodes or {}
        self:Refresh()
    end

    function tree:SetOnSelect(callback)
        self.onSelect = callback
    end

    function tree:SetOnRightClick(callback)
        self.onRightClick = callback
    end

    function tree:SetSelected(id)
        self.selectedId = id
        self:UpdateSelection()
    end

    function tree:ExpandNode(id)
        self.expanded[id] = true
        self:Refresh()
    end

    function tree:CollapseNode(id)
        self.expanded[id] = nil
        self:Refresh()
    end

    function tree:ExpandAll()
        local function markExpand(nodes)
            for _, node in ipairs(nodes) do
                if node.children and #node.children > 0 then
                    self.expanded[node.id] = true
                    markExpand(node.children)
                end
            end
        end
        markExpand(self.nodes)
        self:Refresh()
    end

    function tree:CollapseAll()
        wipe(self.expanded)
        self:Refresh()
    end

    -- Scrollbar drag
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
        dragStartOffset = tree.scrollOffset
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

        local totalH = #tree.flatList * ROW_HEIGHT
        local viewH = tree.scrollFrame:GetHeight()
        local maxScroll = math.max(0, totalH - viewH)
        local trackH = tree.scrollbar:GetHeight() - tree.thumb:GetHeight()
        if trackH <= 0 then return end

        local scrollRatio = delta / trackH
        tree.scrollOffset = DF.Util:Clamp(dragStartOffset + scrollRatio * maxScroll, 0, maxScroll)
        tree:UpdateRows()
        tree:UpdateThumb()
    end)

    -- Mouse wheel
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        local totalH = #tree.flatList * ROW_HEIGHT
        local viewH = tree.scrollFrame:GetHeight()
        local maxScroll = math.max(0, totalH - viewH)
        tree.scrollOffset = DF.Util:Clamp(tree.scrollOffset - delta * ROW_HEIGHT * 3, 0, maxScroll)
        tree:UpdateRows()
        tree:UpdateThumb()
    end)

    -- Resize handler (deferred to avoid mid-layout calculations)
    container:SetScript("OnSizeChanged", function()
        C_Timer.After(0, function()
            local w = tree.scrollFrame:GetWidth()
            if w > 0 then
                tree.content:SetWidth(w)
            end
            tree:UpdateRows()
            tree:UpdateThumb()
        end)
    end)

    return tree
end
