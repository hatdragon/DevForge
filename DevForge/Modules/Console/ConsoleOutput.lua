local _, DF = ...

DF.ConsoleOutput = {}

local Output = DF.ConsoleOutput

function Output:Create(parent)
    local pane = DF.Widgets:CreateScrollPane(parent, true)
    pane.frame:SetBackdropColor(unpack(DF.Colors.inputBg))

    -- Output text display using EditBox for selectable text
    local editbox = CreateFrame("EditBox", nil, pane:GetContent())
    editbox:SetPoint("TOPLEFT", 6, -4)
    editbox:SetPoint("RIGHT", -6, 0)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(DF.Theme:CodeFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:SetHyperlinksEnabled(false)

    -- Read-only but copyable: block character input, revert any other
    -- modifications (backspace, delete, paste), but keep keyboard enabled
    -- so Ctrl+C / Ctrl+A work.
    editbox:SetScript("OnChar", function() end)
    editbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editbox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    local output = {
        frame = pane.frame,
        pane = pane,
        editbox = editbox,
        lines = {},
        text = "",
    }

    -- Revert any user modification (backspace, delete, paste) while
    -- allowing programmatic SetText via Rebuild/Clear.
    editbox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(output.text)
        end
    end)

    function output:AddLine(text)
        self.lines[#self.lines + 1] = text
        self:Rebuild()
    end

    function output:AddLines(textLines)
        for _, line in ipairs(textLines) do
            self.lines[#self.lines + 1] = line
        end
        self:Rebuild()
    end

    function output:Rebuild()
        self.text = table.concat(self.lines, "\n")
        self.editbox:SetText(self.text)

        -- Update content height (deferred so editbox has time to reflow)
        C_Timer.After(0, function()
            local h = self.editbox:GetHeight()
            if h and h > 0 then
                self.pane:SetContentHeight(h + 10)
            end
            self.pane:ScrollToBottom()
        end)
    end

    function output:Clear()
        wipe(self.lines)
        self.text = ""
        self.editbox:SetText("")
        self.pane:SetContentHeight(0)
    end

    function output:GetText()
        return self.text
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

    return output
end
