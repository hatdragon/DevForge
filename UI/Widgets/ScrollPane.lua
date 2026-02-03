local _, DF = ...

DF.Widgets = DF.Widgets or {}

function DF.Widgets:CreateScrollPane(parent, showBorder)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    if showBorder then
        DF.Theme:ApplyDarkPanel(container, true)
    end

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", showBorder and 4 or 0, showBorder and -4 or 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(DF.Layout.scrollbarWidth + (showBorder and 4 or 0)), showBorder and 4 or 0)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    -- Scrollbar track
    local scrollbar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    scrollbar:SetWidth(DF.Layout.scrollbarWidth)
    scrollbar:SetPoint("TOPRIGHT", showBorder and -4 or 0, showBorder and -4 or 0)
    scrollbar:SetPoint("BOTTOMRIGHT", showBorder and -4 or 0, showBorder and 4 or 0)
    scrollbar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    scrollbar:SetBackdropColor(0.08, 0.08, 0.10, 0.5)

    -- Scrollbar thumb
    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(DF.Layout.scrollbarWidth - 2)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:SetHeight(40)

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(unpack(DF.Colors.scrollbar))
    thumb.tex = thumbTex

    thumb:EnableMouse(true)
    thumb:SetMovable(true)
    thumb:RegisterForDrag("LeftButton")

    -- State
    local pane = {
        frame = container,
        scrollFrame = scrollFrame,
        content = content,
        scrollbar = scrollbar,
        thumb = thumb,
        contentHeight = 0,
    }

    -- Scrollbar drag behavior
    local isDragging = false
    local dragStartY, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        isDragging = true
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartScroll = scrollFrame:GetVerticalScroll()
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

        local scrollHeight = scrollbar:GetHeight() - thumb:GetHeight()
        if scrollHeight <= 0 then return end

        local maxScroll = pane.contentHeight - scrollFrame:GetHeight()
        if maxScroll <= 0 then return end

        local scrollRatio = delta / scrollHeight
        local newScroll = DF.Util:Clamp(dragStartScroll + scrollRatio * maxScroll, 0, maxScroll)
        scrollFrame:SetVerticalScroll(newScroll)
        pane:UpdateThumb()
    end)

    -- Mouse wheel
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local step = 40
        local maxScroll = math.max(0, pane.contentHeight - scrollFrame:GetHeight())
        local current = scrollFrame:GetVerticalScroll()
        local newScroll = DF.Util:Clamp(current - delta * step, 0, maxScroll)
        scrollFrame:SetVerticalScroll(newScroll)
        pane:UpdateThumb()
    end)

    function pane:SetContentHeight(h)
        self.contentHeight = h
        self.content:SetHeight(math.max(1, h))
        local w = self.scrollFrame:GetWidth()
        if w > 0 then
            self.content:SetWidth(w)
        end
        self:UpdateThumb()
    end

    function pane:UpdateThumb()
        local viewH = self.scrollFrame:GetHeight()
        local totalH = self.contentHeight
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
        local scrollRatio = (maxScroll > 0) and (self.scrollFrame:GetVerticalScroll() / maxScroll) or 0
        local maxThumbOffset = trackH - thumbH
        local offset = scrollRatio * maxThumbOffset

        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.scrollbar, "TOP", 0, -offset)
    end

    function pane:ScrollToBottom()
        local maxScroll = math.max(0, self.contentHeight - self.scrollFrame:GetHeight())
        self.scrollFrame:SetVerticalScroll(maxScroll)
        self:UpdateThumb()
    end

    function pane:ScrollToTop()
        self.scrollFrame:SetVerticalScroll(0)
        self:UpdateThumb()
    end

    function pane:GetScrollFrame()
        return self.scrollFrame
    end

    function pane:GetContent()
        return self.content
    end

    -- Update content width on resize
    container:SetScript("OnSizeChanged", function()
        local w = scrollFrame:GetWidth()
        if w > 0 then
            content:SetWidth(w)
        end
        pane:UpdateThumb()
    end)

    return pane
end
