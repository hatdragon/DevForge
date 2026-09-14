local _, DF = ...

DF.Widgets = DF.Widgets or {}

--[[
    TabStrip: horizontal row of closeable tabs for switching between open
    documents (e.g. open snippets). Overflow scrolls horizontally via mouse
    wheel rather than shrinking tabs or auto-closing anything.

    Usage:
        local strip = DF.Widgets:CreateTabStrip(parent, { tabWidth = 100 })
        strip:SetTabs({ { id = "a", label = "Foo.lua" }, ... })
        strip:SetActive("a")
        strip:SetOnSelect(function(id) ... end)
        strip:SetOnAction(function(action, id) ... end) -- "close"|"closeOthers"|"closeAll"
]]
function DF.Widgets:CreateTabStrip(parent, opts)
    opts = opts or {}
    local tabWidth = opts.tabWidth or DF.Layout.tabWidth
    local height = opts.height or DF.Layout.tabHeight

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(height)
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    frame:SetBackdropColor(unpack(DF.Colors.sidebarHeaderBg))

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetAllPoints()

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, height)
    scrollFrame:SetScrollChild(content)

    local strip = {
        frame = frame,
        rows = {},
        tabs = {},  -- ordered { {id, label}, ... }
        activeId = nil,
        onSelect = nil,
        onAction = nil,
    }

    local contextMenu = DF.Widgets:CreateDropDown()

    local function GetTabButton(index)
        if strip.rows[index] then
            strip.rows[index]:Show()
            return strip.rows[index]
        end

        local tab = CreateFrame("Button", nil, content, "BackdropTemplate")
        tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        tab:SetSize(tabWidth, height)
        tab:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })

        local closeBtn = CreateFrame("Button", nil, tab)
        closeBtn:SetSize(14, 14)
        closeBtn:SetPoint("RIGHT", -6, 0)
        local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
        closeTex:SetFontObject(DF.Theme:UIFont())
        closeTex:SetPoint("CENTER")
        closeTex:SetText("x")
        closeTex:SetTextColor(0.6, 0.6, 0.6, 1)
        closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3, 1) end)
        closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.6, 0.6, 0.6, 1) end)
        closeBtn:SetScript("OnClick", function()
            if strip.onAction then strip.onAction("close", tab.tabId) end
        end)
        tab.closeBtn = closeBtn

        local label = tab:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(DF.Theme:UIFont())
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        tab.label = label

        tab:SetScript("OnEnter", function(self)
            if self.tabId ~= strip.activeId then
                self:SetBackdropColor(unpack(DF.Colors.tabHover))
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if self.tabId ~= strip.activeId then
                self:SetBackdropColor(unpack(DF.Colors.tabInactive))
            end
        end)
        tab:SetScript("OnClick", function(self, button)
            local id = self.tabId
            if button == "MiddleButton" then
                if strip.onAction then strip.onAction("close", id) end
            elseif button == "RightButton" then
                contextMenu:Show(nil, {
                    { text = "Close", func = function()
                        if strip.onAction then strip.onAction("close", id) end
                    end },
                    { text = "Close Others", func = function()
                        if strip.onAction then strip.onAction("closeOthers", id) end
                    end },
                    { text = "Close All", func = function()
                        if strip.onAction then strip.onAction("closeAll", id) end
                    end },
                })
            else
                if strip.onSelect then strip.onSelect(id) end
            end
        end)

        strip.rows[index] = tab
        return tab
    end

    function strip:SetTabs(tabs)
        self.tabs = tabs or {}
        local xOffset = 0
        for i, t in ipairs(self.tabs) do
            local tab = GetTabButton(i)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", content, "TOPLEFT", xOffset, 0)
            tab.tabId = t.id
            tab.label:SetText(t.label or "Untitled")
            xOffset = xOffset + tabWidth
        end
        for i = #self.tabs + 1, #self.rows do
            self.rows[i]:Hide()
        end
        content:SetWidth(math.max(1, xOffset))
        self:UpdateHighlight()
    end

    function strip:UpdateHighlight()
        for _, tab in ipairs(self.rows) do
            if tab:IsShown() then
                if tab.tabId == self.activeId then
                    tab:SetBackdropColor(unpack(DF.Colors.tabActive))
                    tab.label:SetTextColor(0.9, 0.9, 0.9, 1)
                else
                    tab:SetBackdropColor(unpack(DF.Colors.tabInactive))
                    tab.label:SetTextColor(0.65, 0.65, 0.65, 1)
                end
            end
        end
    end

    -- Scroll the strip just enough to bring a tab fully into view
    function strip:ScrollToTab(id)
        for i, t in ipairs(self.tabs) do
            if t.id == id then
                local tabLeft = (i - 1) * tabWidth
                local tabRight = tabLeft + tabWidth
                local viewW = scrollFrame:GetWidth()
                local current = scrollFrame:GetHorizontalScroll()
                if tabLeft < current then
                    scrollFrame:SetHorizontalScroll(tabLeft)
                elseif tabRight > current + viewW then
                    scrollFrame:SetHorizontalScroll(math.max(0, tabRight - viewW))
                end
                return
            end
        end
    end

    function strip:SetActive(id)
        self.activeId = id
        self:UpdateHighlight()
        self:ScrollToTab(id)
    end

    function strip:SetOnSelect(callback)
        self.onSelect = callback
    end

    function strip:SetOnAction(callback)
        self.onAction = callback
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetWidth() - self:GetWidth())
        local current = self:GetHorizontalScroll()
        local newScroll = DF.Util:Clamp(current - delta * 40, 0, maxScroll)
        self:SetHorizontalScroll(newScroll)
    end)

    frame:SetScript("OnSizeChanged", function()
        local maxScroll = math.max(0, content:GetWidth() - scrollFrame:GetWidth())
        if scrollFrame:GetHorizontalScroll() > maxScroll then
            scrollFrame:SetHorizontalScroll(maxScroll)
        end
    end)

    return strip
end
