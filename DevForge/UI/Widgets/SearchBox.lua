local _, DF = ...

DF.Widgets = DF.Widgets or {}

function DF.Widgets:CreateSearchBox(parent, placeholder, height)
    height = height or 24
    placeholder = placeholder or "Search..."

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(height)

    DF.Theme:ApplyInputStyle(frame)

    local editbox = CreateFrame("EditBox", nil, frame)
    editbox:SetPoint("TOPLEFT", 6, -2)
    editbox:SetPoint("BOTTOMRIGHT", -6, 2)
    editbox:SetFontObject(DF.Theme:UIFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:SetAutoFocus(false)
    editbox:SetMaxLetters(200)

    -- Placeholder text
    local placeholderText = editbox:CreateFontString(nil, "OVERLAY")
    placeholderText:SetFontObject(DF.Theme:UIFont())
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder)
    placeholderText:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -4, 0)
    clearBtn:Hide()

    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    clearText:SetFontObject(DF.Theme:UIFont())
    clearText:SetPoint("CENTER", 0, 0)
    clearText:SetText("x")
    clearText:SetTextColor(0.6, 0.6, 0.6, 1)

    clearBtn:SetScript("OnClick", function()
        editbox:SetText("")
        editbox:ClearFocus()
    end)
    clearBtn:SetScript("OnEnter", function()
        clearText:SetTextColor(1, 1, 1, 1)
    end)
    clearBtn:SetScript("OnLeave", function()
        clearText:SetTextColor(0.6, 0.6, 0.6, 1)
    end)

    -- State
    local searchBox = {
        frame = frame,
        editbox = editbox,
        onSearch = nil,
    }

    local debouncedSearch = DF.Util:Debounce(function(text)
        if searchBox.onSearch then
            searchBox.onSearch(text)
        end
    end, DF.DEBOUNCE_MS / 1000)

    editbox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if text and text ~= "" then
            placeholderText:Hide()
            clearBtn:Show()
        else
            placeholderText:Show()
            clearBtn:Hide()
        end
        if userInput then
            debouncedSearch(text)
        end
    end)

    editbox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    editbox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if searchBox.onSearch then
            searchBox.onSearch(self:GetText())
        end
    end)

    function searchBox:SetOnSearch(callback)
        self.onSearch = callback
    end

    function searchBox:GetText()
        return self.editbox:GetText() or ""
    end

    function searchBox:SetText(text)
        self.editbox:SetText(text or "")
    end

    function searchBox:Clear()
        self.editbox:SetText("")
    end

    function searchBox:Focus()
        self.editbox:SetFocus()
    end

    return searchBox
end
