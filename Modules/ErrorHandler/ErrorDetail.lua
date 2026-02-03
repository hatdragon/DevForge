local _, DF = ...

DF.ErrorDetail = {}

local Detail = DF.ErrorDetail

function Detail:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)
    pane.frame:SetBackdropColor(unpack(DF.Colors.inputBg))

    -- Read-only EditBox for selectable text
    local editbox = CreateFrame("EditBox", nil, pane:GetContent())
    editbox:SetPoint("TOPLEFT", 6, -4)
    editbox:SetPoint("RIGHT", -6, 0)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(DF.Theme:CodeFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:EnableKeyboard(false)
    editbox:SetHyperlinksEnabled(false)

    -- Make read-only but allow text selection
    editbox:SetScript("OnChar", function() end)
    editbox:SetScript("OnMouseUp", function(self)
        self:HighlightText()
    end)
    editbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local detail = {
        frame = pane.frame,
        pane = pane,
        editbox = editbox,
        currentId = nil,
    }

    function detail:ShowError(err)
        if not err then
            self.editbox:SetText("")
            self.currentId = nil
            return
        end

        self.currentId = err.id

        local lines = {}

        -- Header
        local typeLabel = (err.type == "warning") and "WARNING" or "ERROR"
        lines[#lines + 1] = "[" .. typeLabel .. "] " .. (err.message or "")
        lines[#lines + 1] = ""

        -- Timestamp + count
        local countStr = ""
        if err.counter and err.counter > 1 then
            countStr = "  (x" .. err.counter .. ")"
        end
        lines[#lines + 1] = "Time: " .. (err.time or "unknown") .. countStr
        lines[#lines + 1] = "Session: " .. (err.session or "?")
        lines[#lines + 1] = ""

        -- Stack trace
        if err.stack and err.stack ~= "" then
            lines[#lines + 1] = "Stack:"
            for line in err.stack:gmatch("[^\n]+") do
                lines[#lines + 1] = "  " .. line
            end
            lines[#lines + 1] = ""
        end

        -- Locals
        if err.locals and err.locals ~= "" then
            lines[#lines + 1] = "Locals:"
            for line in err.locals:gmatch("[^\n]+") do
                lines[#lines + 1] = "  " .. line
            end
        end

        local text = table.concat(lines, "\n")
        self.editbox:SetText(text)

        C_Timer.After(0, function()
            local h = self.editbox:GetHeight()
            if h and h > 0 then
                self.pane:SetContentHeight(h + 10)
            end
            self.pane:ScrollToTop()
        end)
    end

    function detail:Clear()
        self.editbox:SetText("")
        self.currentId = nil
        self.pane:SetContentHeight(0)
    end

    function detail:GetText()
        return self.editbox:GetText()
    end

    -- Handle resize
    pane.frame:SetScript("OnSizeChanged", function()
        local w = pane.scrollFrame:GetWidth()
        if w <= 0 then return end
        pane:GetContent():SetWidth(w)
        editbox:SetWidth(math.max(50, w - 12))
        C_Timer.After(0, function()
            local h = editbox:GetHeight()
            if h and h > 0 then
                pane:SetContentHeight(h + 10)
            end
            pane:UpdateThumb()
        end)
    end)

    return detail
end
