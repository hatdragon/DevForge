local _, DF = ...

DF.ConsoleInput = {}

local Input = DF.ConsoleInput

function Input:Create(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(28)
    DF.Theme:ApplyDarkPanel(frame, true)
    frame:SetBackdropColor(unpack(DF.Colors.inputBg))

    -- Prompt indicator
    local prompt = frame:CreateFontString(nil, "OVERLAY")
    prompt:SetFontObject(DF.Theme:CodeFont())
    prompt:SetPoint("LEFT", 6, 0)
    prompt:SetText(">")
    prompt:SetTextColor(0.4, 0.6, 1, 1)

    -- Input EditBox
    local editbox = CreateFrame("EditBox", nil, frame)
    editbox:SetPoint("LEFT", prompt, "RIGHT", 4, 0)
    editbox:SetPoint("RIGHT", -6, 0)
    editbox:SetHeight(20)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(DF.Theme:CodeFont())
    editbox:SetTextColor(0.83, 0.83, 0.83, 1)
    editbox:SetMaxLetters(4096)

    local input = {
        frame = frame,
        editbox = editbox,
        onExecute = nil,   -- callback(code)
    }

    -- Enter = execute, Shift+Enter = newline
    editbox:SetScript("OnEnterPressed", function(self)
        if IsShiftKeyDown() then
            self:Insert("\n")
            return
        end

        local text = self:GetText()
        if text and text ~= "" then
            if input.onExecute then
                input.onExecute(text)
            end
            self:SetText("")
        end
    end)

    -- Tab inserts spaces
    editbox:SetScript("OnTabPressed", function(self)
        self:Insert("    ")
    end)

    -- Escape clears focus
    editbox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- Up/Down arrow for history
    editbox:SetScript("OnKeyDown", function(self, key)
        if key == "UP" then
            local text = DF.ConsoleHistory:Up(self:GetText())
            if text then
                self:SetText(text)
                self:SetCursorPosition(#text)
            end
        elseif key == "DOWN" then
            local text = DF.ConsoleHistory:Down(self:GetText())
            if text then
                self:SetText(text)
                self:SetCursorPosition(#text)
            end
        end
    end)

    function input:SetOnExecute(callback)
        self.onExecute = callback
    end

    function input:GetText()
        return self.editbox:GetText() or ""
    end

    function input:SetText(text)
        self.editbox:SetText(text or "")
    end

    function input:Focus()
        self.editbox:SetFocus()
    end

    function input:ClearFocus()
        self.editbox:ClearFocus()
    end

    return input
end
